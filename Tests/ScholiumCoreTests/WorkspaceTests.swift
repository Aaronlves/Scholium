import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Scholium workspace registration")
struct WorkspaceTests {
    @Test("The Works role exposes Works capabilities")
    func worksRoleCapabilities() {
        #expect(VaultRole.draftProject.displayName == "Works")
        #expect(VaultRole.draftProject.allowsCritique)
        #expect(!VaultRole.sourceCorpus.allowsCritique)
        #expect(!VaultRole.topicKnowledge.allowsCritique)
    }

    @Test("Default workspace uses concise researcher-facing vault names")
    func defaultWorkspaceDisplayNames() {
        #expect(WorkspaceVaultSlot.paperAnalysis.displayName == "Analyses")
        #expect(WorkspaceVaultSlot.topicKnowledge.displayName == "Topics")
        #expect(WorkspaceVaultSlot.output.displayName == "Works")
    }

    @Test("Vault registration is stable and role-aware")
    func vaultRegistration() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))

        let first = try await registry.register(path: vault, name: "Sources", role: .sources)
        let updated = try await registry.register(path: vault, name: "Paper Analyses", role: .sources)

        #expect(first.id == updated.id)
        #expect(try await registry.resolve("Paper Analyses").id == first.id)
        #expect(try await registry.allVaults().count == 1)
    }

    @Test("Three-vault workspace rejects equal and nested folders")
    func threeVaultOverlapValidation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let papers = base.appendingPathComponent("papers", isDirectory: true)
        let nestedTopics = papers.appendingPathComponent("topics", isDirectory: true)
        let output = base.appendingPathComponent("output", isDirectory: true)
        for url in [papers, nestedTopics, output] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))

        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.configureTriptych(
                id: UUID(),
                paperAnalysis: (papers, UUID()),
                topicKnowledge: (nestedTopics, UUID()),
                output: (output, UUID())
            )
        }
    }

    @Test("Three vault roles reject one repeated portable identity")
    func threeVaultIdentityValidation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let urls = try makeTriptychFolders(in: base)
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        let registry = WorkspaceRegistry(storageURL: storage)
        let repeatedID = UUID()

        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.configureTriptych(
                id: UUID(),
                paperAnalysis: (urls.analyses, repeatedID),
                topicKnowledge: (urls.topics, repeatedID),
                output: (urls.works, repeatedID)
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: WorkspaceRegistry.registryURL(storageURL: storage).path
        ))
    }

    @Test("Three independent sibling vaults persist as one workspace")
    func threeVaultWorkspacePersists() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let papers = base.appendingPathComponent("papers", isDirectory: true)
        let topics = base.appendingPathComponent("topics", isDirectory: true)
        let output = base.appendingPathComponent("output", isDirectory: true)
        for url in [papers, topics, output] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        let registry = WorkspaceRegistry(storageURL: storage)
        let paperID = UUID()
        let topicID = UUID()
        let outputID = UUID()

        let assignment = try await registry.configureTriptych(
            id: UUID(),
            paperAnalysis: (papers, paperID),
            topicKnowledge: (topics, topicID),
            output: (output, outputID)
        )
        let restored = try await WorkspaceRegistry(storageURL: storage).defaultTriptych()

        #expect(assignment.hasCommonParent)
        #expect(assignment.vault(for: .paperAnalysis)?.role == .sourceCorpus)
        #expect(assignment.vault(for: .topicKnowledge)?.role == .topicKnowledge)
        #expect(assignment.vault(for: .output)?.role == .draftProject)
        #expect(restored?.workspace.paperAnalysisVaultID == assignment.workspace.paperAnalysisVaultID)
        #expect(restored?.vault(for: .output)?.canonicalPath == output.path)
    }

    @Test("Several complete Triptychs persist without replacing one another")
    func multipleTriptychsPersist() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let firstRoot = base.appendingPathComponent("Metaethics", isDirectory: true)
        let secondRoot = base.appendingPathComponent("Mind", isDirectory: true)
        let firstURLs = try makeTriptychFolders(in: firstRoot)
        let secondURLs = try makeTriptychFolders(in: secondRoot)
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        let firstID = UUID()
        let secondID = UUID()

        let first = try await registry.configureTriptych(
            id: firstID,
            name: "Metaethics",
            paperAnalysis: (firstURLs.analyses, UUID()),
            topicKnowledge: (firstURLs.topics, UUID()),
            output: (firstURLs.works, UUID())
        )
        let second = try await registry.configureTriptych(
            id: secondID,
            name: "Mind",
            paperAnalysis: (secondURLs.analyses, UUID()),
            topicKnowledge: (secondURLs.topics, UUID()),
            output: (secondURLs.works, UUID())
        )

        let restored = try await WorkspaceRegistry(
            storageURL: base.appendingPathComponent("registry", isDirectory: true)
        ).allTriptychs()
        #expect(restored.map(\.id) == [firstID, secondID])
        #expect(restored.first?.vault(for: .paperAnalysis)?.name == "Analyses")
        #expect(restored.last?.vault(for: .paperAnalysis)?.name == "Analyses")
        #expect(first.vault(for: .output)?.canonicalPath == firstURLs.works.path)
        #expect(second.vault(for: .output)?.canonicalPath == secondURLs.works.path)
        #expect(try await registry.triptych(id: secondID)?.id == secondID)
        #expect(try await registry.triptych(id: firstID)?.id == firstID)
        #expect(try await registry.resolve(first.vault(for: .paperAnalysis)!.id.uuidString).id
            == first.vault(for: .paperAnalysis)!.id)
        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.resolve("Analyses")
        }
    }

    @Test("Two Triptychs cannot share one portable control directory")
    func portableControlDirectoryCannotCollide() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let firstAnalyses = base.appendingPathComponent("First/Analyses", isDirectory: true)
        let firstTopics = base.appendingPathComponent("First/Topics", isDirectory: true)
        let secondAnalyses = base.appendingPathComponent("Second/Analyses", isDirectory: true)
        let secondTopics = base.appendingPathComponent("Second/Topics", isDirectory: true)
        let firstWorks = base.appendingPathComponent("Shared/First Works", isDirectory: true)
        let secondWorks = base.appendingPathComponent("Shared/Second Works", isDirectory: true)
        for url in [firstAnalyses, firstTopics, secondAnalyses, secondTopics, firstWorks, secondWorks] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        _ = try await registry.configureTriptych(
            id: UUID(),
            paperAnalysis: (firstAnalyses, UUID()),
            topicKnowledge: (firstTopics, UUID()),
            output: (firstWorks, UUID())
        )

        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.configureTriptych(
                id: UUID(),
                paperAnalysis: (secondAnalyses, UUID()),
                topicKnowledge: (secondTopics, UUID()),
                output: (secondWorks, UUID())
            )
        }
    }

    @Test("Changing one Triptych leaves another Triptych and its vault UUIDs intact")
    func oneTriptychCanChangeIndependently() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let firstURLs = try makeTriptychFolders(in: base.appendingPathComponent("First", isDirectory: true))
        let secondURLs = try makeTriptychFolders(in: base.appendingPathComponent("Second", isDirectory: true))
        let replacementTopics = base.appendingPathComponent("First/New Topics", isDirectory: true)
        try FileManager.default.createDirectory(at: replacementTopics, withIntermediateDirectories: true)
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        let firstID = UUID()
        let secondID = UUID()
        let firstAnalysesID = UUID()
        let firstTopicsID = UUID()
        let firstWorksID = UUID()
        let secondAnalysesID = UUID()
        let secondTopicsID = UUID()
        let secondWorksID = UUID()
        _ = try await registry.configureTriptych(
            id: firstID,
            paperAnalysis: (firstURLs.analyses, firstAnalysesID),
            topicKnowledge: (firstURLs.topics, firstTopicsID),
            output: (firstURLs.works, firstWorksID)
        )
        _ = try await registry.configureTriptych(
            id: secondID,
            paperAnalysis: (secondURLs.analyses, secondAnalysesID),
            topicKnowledge: (secondURLs.topics, secondTopicsID),
            output: (secondURLs.works, secondWorksID)
        )

        _ = try await registry.configureTriptych(
            id: firstID,
            paperAnalysis: (firstURLs.analyses, firstAnalysesID),
            topicKnowledge: (replacementTopics, firstTopicsID),
            output: (firstURLs.works, firstWorksID)
        )

        let second = try #require(await registry.triptych(id: secondID))
        let first = try #require(await registry.triptych(id: firstID))
        #expect(first.vault(for: .topicKnowledge)?.id == firstTopicsID)
        #expect(first.vault(for: .topicKnowledge)?.canonicalPath == replacementTopics.path)
        #expect(second.vault(for: .paperAnalysis)?.id == secondAnalysesID)
        #expect(second.vault(for: .topicKnowledge)?.id == secondTopicsID)
        #expect(second.vault(for: .output)?.id == secondWorksID)
        #expect(second.vault(for: .topicKnowledge)?.canonicalPath == secondURLs.topics.path)
    }

    @Test("Portable Triptych identity reconciliation preserves every vault identity")
    func triptychIdentityReconciliation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let urls = try makeTriptychFolders(in: base.appendingPathComponent("Domain", isDirectory: true))
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        let oldTriptychID = UUID()
        let stableTriptychID = UUID()
        let analysesID = UUID()
        let topicsID = UUID()
        let worksID = UUID()
        _ = try await registry.configureTriptych(
            id: oldTriptychID,
            paperAnalysis: (urls.analyses, analysesID),
            topicKnowledge: (urls.topics, topicsID),
            output: (urls.works, worksID)
        )

        let repaired = try await registry.reidentifyTriptych(
            id: oldTriptychID,
            as: stableTriptychID
        )

        #expect(repaired.id == stableTriptychID)
        #expect(repaired.vault(for: .paperAnalysis)?.id == analysesID)
        #expect(repaired.vault(for: .topicKnowledge)?.id == topicsID)
        #expect(repaired.vault(for: .output)?.id == worksID)
        #expect(try await registry.triptych(id: oldTriptychID) == nil)
        #expect(try await registry.defaultTriptych()?.id == stableTriptychID)
    }

    @Test("A damaged current registry is preserved before relinking")
    func corruptRegistryIsPreservedBeforeRelinking() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let urls = try makeTriptychFolders(in: base.appendingPathComponent("Domain", isDirectory: true))
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let registryURL = WorkspaceRegistry.registryURL(storageURL: storage)
        let damaged = Data("researcher recovery data, not valid JSON".utf8)
        try damaged.write(to: registryURL)
        let registry = WorkspaceRegistry(storageURL: storage)

        guard case .malformedCurrentSchema = await registry.health() else {
            Issue.record("A malformed registry did not report its repairable health.")
            return
        }
        await #expect(throws: WorkspaceRegistryError.self) {
            _ = try await registry.allTriptychs()
        }
        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.configureTriptych(
                paperAnalysis: (urls.analyses, UUID()),
                topicKnowledge: (urls.topics, UUID()),
                output: (urls.works, UUID())
            )
        }
        #expect(try Data(contentsOf: registryURL) == damaged)

        let backup = try WorkspaceRegistry.preserveMalformedRegistryForRelinking(
            storageURL: storage
        )
        #expect(!FileManager.default.fileExists(atPath: registryURL.path))
        #expect(try Data(contentsOf: backup) == damaged)
        #expect(await registry.health().isHealthy)
        #expect(try await registry.allTriptychs().isEmpty)
    }

    @Test("Removing a local Triptych registration preserves source folders and unrelated registrations")
    func removingTriptychRegistrationPreservesSourceAndUnrelatedRegistration() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let firstURLs = try makeTriptychFolders(
            in: base.appendingPathComponent("First", isDirectory: true)
        )
        let secondURLs = try makeTriptychFolders(
            in: base.appendingPathComponent("Second", isDirectory: true)
        )
        let marker = firstURLs.analyses.appendingPathComponent("Keep.md")
        let markerBytes = Data("research bytes stay authoritative".utf8)
        try markerBytes.write(to: marker)
        let registry = WorkspaceRegistry(
            storageURL: base.appendingPathComponent("registry", isDirectory: true)
        )
        let first = try await registry.configureTriptych(
            name: "First",
            paperAnalysis: (firstURLs.analyses, UUID()),
            topicKnowledge: (firstURLs.topics, UUID()),
            output: (firstURLs.works, UUID())
        )
        let second = try await registry.configureTriptych(
            name: "Second",
            paperAnalysis: (secondURLs.analyses, UUID()),
            topicKnowledge: (secondURLs.topics, UUID()),
            output: (secondURLs.works, UUID())
        )

        try await registry.removeTriptychRegistration(id: first.id)

        #expect(try Data(contentsOf: marker) == markerBytes)
        #expect(try await registry.triptych(id: first.id) == nil)
        #expect(try await registry.defaultTriptych()?.id == second.id)
        #expect(try await registry.allTriptychs().map(\.id) == [second.id])
        #expect(try await registry.allVaults().count == 3)

        try await registry.removeTriptychRegistration(id: second.id)
        #expect(try await registry.defaultTriptych() == nil)
        #expect(try await registry.allTriptychs().isEmpty)
        #expect(try await registry.allVaults().isEmpty)
        #expect(FileManager.default.fileExists(atPath: secondURLs.works.path))
    }

    @Test("A readable registry with broken references is not a healthy empty workspace")
    func brokenRegistryReferencesFailClosed() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let urls = try makeTriptychFolders(in: base.appendingPathComponent("Domain", isDirectory: true))
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        let registry = WorkspaceRegistry(storageURL: storage)
        _ = try await registry.configureTriptych(
            paperAnalysis: (urls.analyses, UUID()),
            topicKnowledge: (urls.topics, UUID()),
            output: (urls.works, UUID())
        )
        let registryURL = WorkspaceRegistry.registryURL(storageURL: storage)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any]
        )
        var vaults = try #require(object["vaults"] as? [[String: Any]])
        vaults.removeFirst()
        object["vaults"] = vaults
        let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try damaged.write(to: registryURL)

        let reopened = WorkspaceRegistry(storageURL: storage)
        guard case .malformedCurrentSchema = await reopened.health() else {
            Issue.record("Broken Triptych references were accepted as a healthy registry.")
            return
        }
        await #expect(throws: WorkspaceRegistryError.self) {
            _ = try await reopened.allTriptychs()
        }
        #expect(try Data(contentsOf: registryURL) == damaged)
    }

    @Test("A newer registry is visible but never preserved or replaced by relinking")
    func newerRegistryIsNeverOverwritten() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let registryURL = WorkspaceRegistry.registryURL(storageURL: storage)
        let newer = Data(#"{"schemaVersion":4}"#.utf8)
        try newer.write(to: registryURL)
        let registry = WorkspaceRegistry(storageURL: storage)

        #expect(await registry.health() == .unsupportedNewerSchema(4))
        await #expect(throws: WorkspaceRegistryError.self) {
            _ = try await registry.allTriptychs()
        }
        #expect(throws: WorkspaceRegistryError.self) {
            try WorkspaceRegistry.preserveMalformedRegistryForRelinking(storageURL: storage)
        }
        #expect(try Data(contentsOf: registryURL) == newer)
    }

    @Test("An unreadable registry is reported as I/O failure and never relinked")
    func unreadableRegistryRemainsInPlace() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        let registryURL = WorkspaceRegistry.registryURL(storageURL: storage)
        try FileManager.default.createDirectory(at: registryURL, withIntermediateDirectories: true)
        let registry = WorkspaceRegistry(storageURL: storage)

        guard case .ioFailure = await registry.health() else {
            Issue.record("A registry that cannot be read did not report I/O failure.")
            return
        }
        await #expect(throws: WorkspaceRegistryError.self) {
            _ = try await registry.allTriptychs()
        }
        #expect(throws: WorkspaceRegistryError.self) {
            try WorkspaceRegistry.preserveMalformedRegistryForRelinking(storageURL: storage)
        }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: registryURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("A workspace folder can be changed without duplicate-name failure")
    func threeVaultWorkspacePathCanChange() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let papers = base.appendingPathComponent("papers", isDirectory: true)
        let topics = base.appendingPathComponent("topics", isDirectory: true)
        let newTopics = base.appendingPathComponent("topics-new", isDirectory: true)
        let output = base.appendingPathComponent("output", isDirectory: true)
        for url in [papers, topics, newTopics, output] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        let triptychID = UUID()
        let original = try await registry.configureTriptych(
            id: triptychID,
            paperAnalysis: (papers, UUID()),
            topicKnowledge: (topics, UUID()),
            output: (output, UUID())
        )
        let paperID = try #require(original.vault(for: .paperAnalysis)?.id)
        let outputID = try #require(original.vault(for: .output)?.id)

        let changed = try await registry.configureTriptych(
            id: triptychID,
            paperAnalysis: (papers, paperID),
            topicKnowledge: (newTopics, UUID()),
            output: (output, outputID)
        )

        #expect(changed.vault(for: .topicKnowledge)?.canonicalPath == newTopics.path)
        #expect(try await registry.allVaults().filter { $0.role == .topicKnowledge }.count == 1)
    }

    private func makeTriptychFolders(
        in root: URL
    ) throws -> (analyses: URL, topics: URL, works: URL) {
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        for url in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return (analyses, topics, works)
    }

    @Test("One workspace registration owns identity, bookmarks, and portable access")
    func unifiedRegistrationOwnsMachineAccess() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let folders = try makeTriptychFolders(in: base)
        let registry = WorkspaceRegistry(storageURL: base)
        let analysesID = UUID()
        let topicsID = UUID()
        let worksID = UUID()
        let vaultBookmarks: [WorkspaceVaultSlot: Data] = [
            .paperAnalysis: Data("analyses".utf8),
            .topicKnowledge: Data("topics".utf8),
            .output: Data("works".utf8),
        ]
        let portable = PortableControlAccess(
            canonicalContainerPath: base.path,
            bookmarkData: Data("container".utf8)
        )

        _ = try await registry.configureTriptych(
            paperAnalysis: (folders.analyses, analysesID),
            topicKnowledge: (folders.topics, topicsID),
            output: (folders.works, worksID),
            vaultBookmarks: vaultBookmarks,
            portableControlAccess: portable
        )

        #expect(try await registry.identity(
            forCanonicalPath: folders.topics.path
        )?.bookmarkData == vaultBookmarks[.topicKnowledge])
        #expect(try await registry.portableAccess(
            forWorksURL: folders.works
        ) == portable)
        #expect(FileManager.default.fileExists(
            atPath: base.appendingPathComponent(
                "workspace-registration-v3.json"
            ).path
        ))
    }

}
