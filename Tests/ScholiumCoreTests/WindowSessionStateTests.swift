import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("External window-session persistence")
struct WindowSessionStateTests {
    @Test("A snapshot round-trips outside research vaults")
    func roundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let id = UUID()
        let triptychID = UUID()
        let vaultID = UUID()
        let topicVaultID = UUID()
        let snapshot = WindowSessionSnapshot(
            id: id,
            triptychID: triptychID,
            vaultID: vaultID,
            openTabs: ["A.md", "B.md"],
            activeTab: "B.md",
            navigationHistory: ["A.md", "B.md", "A.md"],
            navigationIndex: 1,
            documentModes: ["A.md": "read", "B.md": "livePreview"],
            scrollPositions: ["A.md": 0.25],
            inspectorMode: "outgoing",
            inspectorVisible: true,
            contentDestination: .document,
            searchState: SearchWorkspaceState(query: "reasons", scope: .allWorkspace),
            documentTextScale: 2.0,
            qualifiedNavigationHistory: [
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: "A.md"),
                VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: "B.md"),
            ],
            qualifiedNavigationIndex: 1,
            recentNotes: WindowRecentNotes(references: [
                VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: "B.md"),
            ]),
            vaultPresentations: [
                WindowVaultPresentationSnapshot(
                    vaultID: vaultID,
                    openTabs: ["A.md", "B.md"],
                    activeTab: "B.md",
                    documentModes: ["B.md": "livePreview"],
                    scrollPositions: ["B.md": 0.5]
                ),
                WindowVaultPresentationSnapshot(
                    vaultID: topicVaultID,
                    openTabs: ["Topic.md"],
                    activeTab: "Topic.md"
                ),
            ]
        )

        try await store.save(snapshot)
        let restored = try #require(try await store.load(id: id))
        #expect(restored == snapshot)
        #expect(restored.contentDestination == .document)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("A.md").path))
    }

    @Test("A legacy snapshot without Triptych identity remains readable")
    func legacySnapshotCompatibility() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let vaultID = UUID()
        let directory = root.appendingPathComponent("Window Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {
          "id": "\(id.uuidString)",
          "vaultID": "\(vaultID.uuidString)",
          "openTabs": [],
          "navigationHistory": [],
          "navigationIndex": -1,
          "documentModes": {},
          "scrollPositions": {},
          "inspectorMode": "incoming",
          "searchState": { "query": "", "scope": "currentVault", "selectedRoles": [] }
        }
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(id.uuidString).json"))

        let restored = try #require(try await WindowSessionSnapshotStore(
            applicationSupportURL: root
        ).load(id: id))
        #expect(restored.triptychID == nil)
        #expect(restored.vaultID == vaultID)
        #expect(restored.documentTextScale == nil)
        #expect(restored.qualifiedNavigationHistory == nil)
        #expect(restored.recentNotes == nil)
        #expect(restored.vaultPresentations == nil)
    }

    @Test("Retired Home, Search, and Canvas destinations restore to the document")
    func retiredContentDestinationCompatibility() throws {
        let decoder = JSONDecoder()

        let home = try decoder.decode(
            WindowContentDestination.self,
            from: Data(#""home""#.utf8)
        )
        let search = try decoder.decode(
            WindowContentDestination.self,
            from: Data(#""search""#.utf8)
        )
        let canvas = try decoder.decode(
            WindowContentDestination.self,
            from: Data(#""canvas""#.utf8)
        )

        #expect(home == .document)
        #expect(search == .document)
        #expect(canvas == .document)
    }

    @Test("Recent Notes is a bounded unique most-recent-first history")
    func recentNotesOrdering() {
        let vaultID = UUID()
        var recent = WindowRecentNotes(references: (0..<12).map {
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: "\($0).md")
        })

        #expect(recent.references.count == WindowRecentNotes.maximumCount)
        #expect(recent.references.first?.relativePath == "0.md")
        #expect(recent.references.last?.relativePath == "9.md")

        recent.record(VaultQualifiedNoteID(vaultID: vaultID, relativePath: "5.md"))
        #expect(recent.references.first?.relativePath == "5.md")
        #expect(recent.references.count == WindowRecentNotes.maximumCount)
        #expect(recent.references.count(where: { $0.relativePath == "5.md" }) == 1)

        recent.record(VaultQualifiedNoteID(vaultID: vaultID, relativePath: "New.md"))
        #expect(recent.references.first?.relativePath == "New.md")
        #expect(!recent.references.contains(where: { $0.relativePath == "9.md" }))
    }

    @Test("Recent Notes normalization is vault-scoped and restriction is Triptych-scoped")
    func recentNotesScope() {
        let analysisVaultID = UUID()
        let topicVaultID = UUID()
        let unrelatedVaultID = UUID()
        let recent = WindowRecentNotes(references: [
            VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Missing.md"),
            VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
            VaultQualifiedNoteID(vaultID: unrelatedVaultID, relativePath: "Other.md"),
        ])

        let normalized = recent.normalized(
            vaultID: analysisVaultID,
            availablePaths: ["Present.md"]
        )
        #expect(normalized.references == [
            VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
            VaultQualifiedNoteID(vaultID: unrelatedVaultID, relativePath: "Other.md"),
        ])
        #expect(normalized.restricted(to: [analysisVaultID, topicVaultID]).references == [
            VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
        ])
    }

    @Test("Recent Notes migration preserves order and removes destination duplicates")
    func recentNotesPathMigration() {
        let vaultID = UUID()
        let peerVaultID = UUID()
        let migrated = WindowRecentNotes(references: [
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Old.md"),
            VaultQualifiedNoteID(vaultID: peerVaultID, relativePath: "Old.md"),
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: "New.md"),
        ]).migratingPath(vaultID: vaultID, from: "Old.md", to: "New.md")

        #expect(migrated.references == [
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: "New.md"),
            VaultQualifiedNoteID(vaultID: peerVaultID, relativePath: "Old.md"),
        ])
    }

    @Test("Restoration drops missing notes and preserves chronological history")
    func normalization() {
        let snapshot = WindowSessionSnapshot(
            openTabs: ["A.md", "Missing.md", "A.md"],
            activeTab: "Missing.md",
            navigationHistory: ["A.md", "Missing.md", "B.md", "A.md"],
            navigationIndex: 2,
            documentModes: ["A.md": "source", "Missing.md": "read"],
            scrollPositions: ["B.md": 0.8, "Missing.md": 0.2]
        )

        let restored = snapshot.normalized(availablePaths: ["A.md", "B.md"])
        #expect(restored.openTabs == ["A.md"])
        #expect(restored.activeTab == "A.md")
        #expect(restored.navigationHistory == ["A.md", "B.md", "A.md"])
        #expect(restored.navigationIndex == 1)
        #expect(restored.documentModes == ["A.md": "source"])
        #expect(restored.scrollPositions == ["B.md": 0.8])
    }

    @Test("Removing a window session is idempotent")
    func remove() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let snapshot = WindowSessionSnapshot()
        try await store.save(snapshot)
        try await store.remove(id: snapshot.id)
        try await store.remove(id: snapshot.id)
        #expect(try await store.load(id: snapshot.id) == nil)
    }

    @Test("A confirmed note move migrates every window presentation reference in that vault")
    func pathMigration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let vaultID = UUID()
        let matching = WindowSessionSnapshot(
            vaultID: vaultID,
            openTabs: ["Old.md", "Other.md"],
            activeTab: "Old.md",
            navigationHistory: ["Other.md", "Old.md"],
            navigationIndex: 1,
            documentModes: ["Old.md": "livePreview"],
            scrollPositions: ["Old.md": 0.6]
        )
        let otherVault = WindowSessionSnapshot(
            vaultID: UUID(),
            openTabs: ["Old.md"],
            activeTab: "Old.md"
        )
        try await store.save(matching)
        try await store.save(otherVault)

        try await store.migratePath(vaultID: vaultID, from: "Old.md", to: "New.md")

        let migrated = try #require(try await store.load(id: matching.id))
        #expect(migrated.openTabs == ["New.md", "Other.md"])
        #expect(migrated.activeTab == "New.md")
        #expect(migrated.navigationHistory == ["Other.md", "New.md"])
        #expect(migrated.documentModes == ["New.md": "livePreview"])
        #expect(migrated.scrollPositions == ["New.md": 0.6])
        #expect(try await store.load(id: otherVault.id) == otherVault)
    }

    @Test("A move migrates inactive-vault tabs and qualified history")
    func qualifiedPathMigration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let analysisVaultID = UUID()
        let topicVaultID = UUID()
        let snapshot = WindowSessionSnapshot(
            vaultID: topicVaultID,
            openTabs: ["Topic.md"],
            activeTab: "Topic.md",
            qualifiedNavigationHistory: [
                VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Old.md"),
                VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            ],
            qualifiedNavigationIndex: 1,
            recentNotes: WindowRecentNotes(references: [
                VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Old.md"),
                VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            ]),
            vaultPresentations: [
                WindowVaultPresentationSnapshot(
                    vaultID: analysisVaultID,
                    openTabs: ["Old.md"],
                    activeTab: "Old.md",
                    documentModes: ["Old.md": "source"],
                    scrollPositions: ["Old.md": 0.75]
                ),
                WindowVaultPresentationSnapshot(
                    vaultID: topicVaultID,
                    openTabs: ["Topic.md"],
                    activeTab: "Topic.md"
                ),
            ]
        )
        try await store.save(snapshot)

        try await store.migratePath(
            vaultID: analysisVaultID,
            from: "Old.md",
            to: "Moved.md"
        )

        let migrated = try #require(try await store.load(id: snapshot.id))
        #expect(migrated.vaultID == topicVaultID)
        #expect(migrated.openTabs == ["Topic.md"])
        #expect(migrated.qualifiedNavigationHistory?.first == VaultQualifiedNoteID(
            vaultID: analysisVaultID,
            relativePath: "Moved.md"
        ))
        #expect(migrated.recentNotes?.references.first == VaultQualifiedNoteID(
            vaultID: analysisVaultID,
            relativePath: "Moved.md"
        ))
        let analysisPresentation = try #require(
            migrated.vaultPresentations?.first(where: { $0.vaultID == analysisVaultID })
        )
        #expect(analysisPresentation.openTabs == ["Moved.md"])
        #expect(analysisPresentation.activeTab == "Moved.md")
        #expect(analysisPresentation.documentModes == ["Moved.md": "source"])
        #expect(analysisPresentation.scrollPositions == ["Moved.md": 0.75])
    }

    @Test("Normalization preserves visits in peer vaults")
    func qualifiedNormalization() {
        let analysisVaultID = UUID()
        let topicVaultID = UUID()
        let snapshot = WindowSessionSnapshot(
            vaultID: analysisVaultID,
            navigationIndex: 1,
            qualifiedNavigationHistory: [
                VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Missing.md"),
                VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
                VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
            ],
            qualifiedNavigationIndex: 1,
            recentNotes: WindowRecentNotes(references: [
                VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Missing.md"),
                VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
                VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
            ]),
            vaultPresentations: [
                WindowVaultPresentationSnapshot(
                    vaultID: analysisVaultID,
                    openTabs: ["Missing.md", "Present.md"],
                    activeTab: "Missing.md"
                ),
                WindowVaultPresentationSnapshot(
                    vaultID: topicVaultID,
                    openTabs: ["Topic.md"],
                    activeTab: "Topic.md"
                ),
            ]
        )

        let normalized = snapshot.normalized(availablePaths: ["Present.md"])
        #expect(normalized.qualifiedNavigationHistory == [
            VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
        ])
        #expect(normalized.qualifiedNavigationIndex == 0)
        #expect(normalized.recentNotes?.references == [
            VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: "Topic.md"),
            VaultQualifiedNoteID(vaultID: analysisVaultID, relativePath: "Present.md"),
        ])
        #expect(normalized.vaultPresentations?.first(where: {
            $0.vaultID == analysisVaultID
        })?.openTabs == ["Present.md"])
        #expect(normalized.vaultPresentations?.first(where: {
            $0.vaultID == topicVaultID
        })?.openTabs == ["Topic.md"])
    }
}
