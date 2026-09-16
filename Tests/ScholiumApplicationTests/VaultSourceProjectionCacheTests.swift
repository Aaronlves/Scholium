import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Fresh-source catalog projection reuse")
struct VaultSourceProjectionCacheTests {
    @Test("A new catalog reuses Search coordinates while reading and parsing current source")
    func freshStartupHit() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.catalog().snapshot(refreshFolders: false)
        #expect(first.measurement.projectedDocuments == 1)
        #expect(first.measurement.restoredSearchProjections == 0)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopened.measurement.projectedDocuments == 0)
        #expect(reopened.measurement.restoredSearchProjections == 1)
        #expect(reopened.documents.map(\.rawContent) == [fixture.source])
        #expect(try Data(contentsOf: fixture.noteURL) == Data(fixture.source.utf8))
        #expect(reopened.sourceVersions == first.sourceVersions)
        #expect(reopened.fileMetadata == first.fileMetadata)
        #expect(reopened.semantics == first.semantics)
        #expect(reopened.searchProjections == first.searchProjections)
    }

    @Test("Same-content atomic replacement reuses projections and refreshes observed file facts")
    func atomicReplacementRefreshesMetadata() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.catalog().snapshot(refreshFolders: false)
        let oldVersion = try #require(first.sourceVersions[Fixture.path])
        try Data(fixture.source.utf8).write(to: fixture.noteURL, options: .atomic)
        let replacementDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: replacementDate], ofItemAtPath: fixture.noteURL.path)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        let newVersion = try #require(reopened.sourceVersions[Fixture.path])
        let newMetadata = try #require(reopened.fileMetadata[Fixture.path])
        #expect(newVersion.fingerprint == oldVersion.fingerprint)
        #expect(newVersion.inode != oldVersion.inode)
        #expect(newMetadata.modificationDate == replacementDate)
        #expect(reopened.fileMetadata != first.fileMetadata)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopened.measurement.restoredSearchProjections == 1)
        #expect(reopened.measurement.projectedDocuments == 0)
        #expect(reopened.documents.map(\.rawContent) == [fixture.source])
        #expect(reopened.searchProjections == first.searchProjections)
    }

    @Test("A same-size edit with restored mtime misses the cache and parses new authored links")
    func sameSizeEditWithRestoredMtime() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.catalog().snapshot(refreshFolders: false)
        let oldMetadata = try #require(first.fileMetadata[Fixture.path])
        let oldDate = try #require(oldMetadata.modificationDate)
        let edited = fixture.source.replacingOccurrences(of: "Target", with: "NewOne")
        #expect(edited.utf8.count == fixture.source.utf8.count)
        try Data(edited.utf8).write(to: fixture.noteURL)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate], ofItemAtPath: fixture.noteURL.path)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopened.measurement.restoredSearchProjections == 0)
        #expect(reopened.measurement.projectedDocuments == 1)
        #expect(reopened.documents.map(\.rawContent) == [edited])
        #expect(reopened.documents.map(\.fingerprint) != first.documents.map(\.fingerprint))
        let semantic = try #require(reopened.semantics[Fixture.path])
        #expect(semantic.links.map(\.target) == ["NewOne"])
        #expect(semantic.fingerprint == reopened.documents.first?.fingerprint)

        let clean = try await fixture.catalog(useCache: false).snapshot(refreshFolders: false)
        #expect(reopened.semantics == clean.semantics)
        #expect(reopened.searchProjections == clean.searchProjections)
    }

    @Test("A deleted source cannot be restored from a persisted Search projection")
    func missingSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = try await fixture.catalog().snapshot(refreshFolders: false)
        #expect(fixture.hasPersistedProjection)
        try FileManager.default.removeItem(at: fixture.noteURL)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        #expect(reopened.documents.isEmpty)
        #expect(reopened.semantics.isEmpty)
        #expect(reopened.searchProjections.isEmpty)
        #expect(reopened.measurement.restoredSearchProjections == 0)
    }

    @Test("A source replaced by a symlink cannot borrow the original cached projection")
    func symlinkSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = try await fixture.catalog().snapshot(refreshFolders: false)
        #expect(fixture.hasPersistedProjection)
        let outside = fixture.root.appendingPathComponent("Outside.md")
        let sentinel = Data(fixture.source.utf8)
        try sentinel.write(to: outside)
        try FileManager.default.removeItem(at: fixture.noteURL)
        try FileManager.default.createSymbolicLink(at: fixture.noteURL, withDestinationURL: outside)

        let catalog = try await fixture.catalog()
        let reopened = try await catalog.snapshot(refreshFolders: false)
        #expect(reopened.documents.isEmpty)
        #expect(reopened.searchProjections.isEmpty)
        #expect(reopened.measurement.restoredSearchProjections == 0)
        // Enumeration excludes symbolic links. A later path hint still cannot
        // bypass the repository's descriptor-relative source authorization.
        await #expect(throws: (any Error).self) {
            try await catalog.apply(upserts: [Fixture.path], deletions: [], refreshFolders: false)
        }
        #expect(try Data(contentsOf: outside) == sentinel)
        #expect(try await catalog.snapshot(refreshFolders: false).documents.isEmpty)
    }

    private struct Fixture {
        static let path = "Note.md"
        let root: URL
        let vaultURL: URL
        let supportURL: URL
        let vaultID: UUID
        let handle: WorkspaceHandle
        let source = "\u{FEFF}---\r\nsummary: 情感 résumé\r\n---\r\n# Émotion 😀\r\n\r\nAuthored [[Target]] and *freedom*.\r\n"

        var noteURL: URL { vaultURL.appendingPathComponent(Self.path) }
        var hasPersistedProjection: Bool {
            let directory = supportURL.appendingPathComponent(
                "Vaults/\(vaultID.uuidString)/source-projections-v1", isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
                .contains { $0.hasSuffix(".projection.json") } == true
        }

        init() async throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/vault-source-projection-tests/\(UUID().uuidString)", isDirectory: true)
            vaultURL = root.appendingPathComponent("Vault", isDirectory: true)
            supportURL = root.appendingPathComponent("Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try Data(source.utf8).write(to: vaultURL.appendingPathComponent(Self.path))
            let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
            let works = root.appendingPathComponent("Works", isDirectory: true)
            for directory in [analyses, works] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            // Configure via the Application boundary, then stop its native
            // watchers. These isolated catalog tests borrow only the existing
            // repository capability and use a separate, initially empty cache.
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: root.appendingPathComponent("Runtime Support", isDirectory: true),
                        workspaceRegistryStorageURL: root.appendingPathComponent("Registry", isDirectory: true))))
            do {
                handle = try await runtime.configureTriptych(
                    paperAnalysisURL: analyses, topicKnowledgeURL: vaultURL,
                    outputURL: works, portableContainerURL: root, triptychName: "Projection cache fixture")
                vaultID = try #require(handle.assignment.vault(for: .topicKnowledge)?.id)
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func catalog(useCache: Bool = true) async throws -> VaultSourceCatalog {
            let services = await handle.services
            let repository = try #require(services.repositories[vaultID])
            if useCache {
                return VaultSourceCatalog(
                    repository: repository, vaultRole: .topicKnowledge,
                    applicationSupportURL: supportURL, vaultID: vaultID)
            }
            return VaultSourceCatalog(repository: repository, vaultRole: .topicKnowledge)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
