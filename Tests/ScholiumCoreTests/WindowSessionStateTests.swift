import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("External window-session persistence")
struct WindowSessionStateTests {
    @Test("One vault-qualified selected document round-trips outside research vaults")
    func roundTrip() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let id = UUID()
        let triptychID = UUID()
        let vaultID = UUID()
        let selected = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "B.md")
        let snapshot = WindowSessionSnapshot(
            id: id,
            triptychID: triptychID,
            vaultID: vaultID,
            selectedDocument: selected,
            documentModes: ["B.md": "livePreview"],
            scrollPositions: ["B.md": 0.25],
            inspectorMode: "outgoing",
            inspectorVisible: true,
            contentDestination: .document,
            searchState: SearchWorkspaceState(scope: .triptych),
            documentTextScale: 2
        )

        try await store.save(snapshot)
        #expect(try await store.load(id: id) == snapshot)
    }

    @Test("Legacy activeTab becomes the sole selected document")
    func legacyActiveTabMigration() throws {
        let id = UUID()
        let vaultID = UUID()
        let source = Data("""
        {
          "id": "\(id.uuidString)",
          "vaultID": "\(vaultID.uuidString)",
          "openTabs": ["A.md", "B.md"],
          "activeTab": "A.md"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WindowSessionSnapshot.self, from: source)
        #expect(decoded.selectedDocument == VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "A.md"
        ))
        #expect(decoded.normalized(availablePaths: ["B.md"]).selectedDocument == VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "B.md"
        ))
    }

    @Test("Legacy openTabs restores only its last valid candidate when activeTab is absent")
    func legacyLastOpenTabMigration() throws {
        let id = UUID()
        let vaultID = UUID()
        let source = Data("""
        {
          "id": "\(id.uuidString)",
          "vaultID": "\(vaultID.uuidString)",
          "openTabs": ["A.md", "B.md"]
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WindowSessionSnapshot.self, from: source)
        #expect(decoded.selectedDocument?.relativePath == "B.md")
    }

    @Test("Legacy custom-tab and history fields disappear on the next save")
    func legacyFieldsAreDecodeOnly() throws {
        let id = UUID()
        let vaultID = UUID()
        let source = Data("""
        {
          "id": "\(id.uuidString)",
          "vaultID": "\(vaultID.uuidString)",
          "openTabs": ["A.md"],
          "activeTab": "A.md",
          "navigationHistory": ["A.md"],
          "navigationIndex": 0,
          "recentNotes": {"references": []}
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WindowSessionSnapshot.self, from: source)
        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["selectedDocument"] != nil)
        #expect(object["openTabs"] == nil)
        #expect(object["activeTab"] == nil)
        #expect(object["navigationHistory"] == nil)
        #expect(object["navigationIndex"] == nil)
        #expect(object["recentNotes"] == nil)
        #expect(object["vaultPresentations"] == nil)
    }

    @Test("Normalization never invents a replacement for a missing selection")
    func normalization() {
        let vaultID = UUID()
        let snapshot = WindowSessionSnapshot(
            vaultID: vaultID,
            selectedDocument: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Missing.md"),
            documentModes: ["Present.md": "source", "Missing.md": "read"],
            scrollPositions: ["Present.md": 0.8, "Missing.md": 0.2]
        )

        let normalized = snapshot.normalized(availablePaths: ["Present.md"])
        #expect(normalized.selectedDocument == nil)
        #expect(normalized.documentModes == ["Present.md": "source"])
        #expect(normalized.scrollPositions == ["Present.md": 0.8])
    }

    @Test("Normalization preserves a selected document from a different browsed vault")
    func normalizationPreservesIndependentLibraryVault() {
        let browsedVaultID = UUID()
        let documentVaultID = UUID()
        let selected = VaultQualifiedNoteID(
            vaultID: documentVaultID,
            relativePath: "Shared.md"
        )
        let snapshot = WindowSessionSnapshot(
            vaultID: browsedVaultID,
            selectedDocument: selected,
            documentModes: ["Shared.md": "livePreview"],
            scrollPositions: ["Shared.md": 0.42]
        )

        let normalized = snapshot.normalized(availablePaths: ["Shared.md"])
        #expect(normalized.vaultID == browsedVaultID)
        #expect(normalized.selectedDocument == selected)
        #expect(normalized.documentModes == ["Shared.md": "livePreview"])
        #expect(normalized.scrollPositions == ["Shared.md": 0.42])
    }

    @Test("A confirmed move migrates only matching vault-qualified selections")
    func pathMigration() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let vaultID = UUID()
        let matching = WindowSessionSnapshot(
            vaultID: vaultID,
            selectedDocument: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Old.md"),
            documentModes: ["Old.md": "livePreview"],
            scrollPositions: ["Old.md": 0.6]
        )
        let peerVaultID = UUID()
        let peer = WindowSessionSnapshot(
            vaultID: peerVaultID,
            selectedDocument: VaultQualifiedNoteID(vaultID: peerVaultID, relativePath: "Old.md")
        )
        try await store.save(matching)
        try await store.save(peer)

        try await store.migratePath(vaultID: vaultID, from: "Old.md", to: "New.md")

        let migrated = try #require(try await store.load(id: matching.id))
        #expect(migrated.selectedDocument?.relativePath == "New.md")
        #expect(migrated.documentModes == ["New.md": "livePreview"])
        #expect(migrated.scrollPositions == ["New.md": 0.6])
        #expect(try await store.load(id: peer.id) == peer)
    }

    @Test("A confirmed move promotes and migrates a decode-only legacy fallback")
    func legacyFallbackPathMigration() throws {
        let id = UUID()
        let vaultID = UUID()
        let source = Data("""
        {
          "id": "\(id.uuidString)",
          "vaultID": "\(vaultID.uuidString)",
          "openTabs": ["Old.md"],
          "activeTab": "Missing.md"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WindowSessionSnapshot.self, from: source)
        let migrated = decoded.migratingPath(
            vaultID: vaultID,
            from: "Old.md",
            to: "New.md"
        )

        #expect(migrated.selectedDocument == VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "New.md"
        ))
        #expect(migrated.normalized(availablePaths: ["New.md"]).selectedDocument == migrated.selectedDocument)

        let modernRoundTrip = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: JSONEncoder().encode(migrated)
        )
        #expect(modernRoundTrip.selectedDocument == migrated.selectedDocument)
    }

    @Test("Retired Home, Search, and Canvas destinations restore to the document")
    func retiredContentDestinationCompatibility() throws {
        for value in ["home", "search", "canvas"] {
            let decoded = try JSONDecoder().decode(
                WindowContentDestination.self,
                from: Data("\"\(value)\"".utf8)
            )
            #expect(decoded == .document)
        }
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
