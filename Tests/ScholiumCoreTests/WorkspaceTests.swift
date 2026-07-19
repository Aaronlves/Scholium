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
        #expect(await registry.allVaults().count == 1)
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
            try await registry.configureDefaultTriptych(
                paperAnalysis: (papers, UUID()),
                topicKnowledge: (nestedTopics, UUID()),
                output: (output, UUID())
            )
        }
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

        let assignment = try await registry.configureDefaultTriptych(
            paperAnalysis: (papers, paperID),
            topicKnowledge: (topics, topicID),
            output: (output, outputID)
        )
        let restored = await WorkspaceRegistry(storageURL: storage).defaultTriptych()

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

        let restored = await WorkspaceRegistry(
            storageURL: base.appendingPathComponent("registry", isDirectory: true)
        ).allTriptychs()
        #expect(restored.map(\.id) == [firstID, secondID])
        #expect(restored.first?.vault(for: .paperAnalysis)?.name == "Analyses")
        #expect(restored.last?.vault(for: .paperAnalysis)?.name == "Analyses")
        #expect(first.vault(for: .output)?.canonicalPath == firstURLs.works.path)
        #expect(second.vault(for: .output)?.canonicalPath == secondURLs.works.path)
        #expect(try await registry.resolveTriptych("Mind").id == secondID)
        #expect(try await registry.resolveTriptych(firstID.uuidString).id == firstID)
        #expect(try await registry.resolve(first.vault(for: .paperAnalysis)!.id.uuidString).id
            == first.vault(for: .paperAnalysis)!.id)
        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.resolve("Analyses")
        }
    }

    @Test("Duplicate Triptych names require a UUID selector")
    func duplicateTriptychNamesAreAmbiguous() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let firstURLs = try makeTriptychFolders(in: base.appendingPathComponent("First", isDirectory: true))
        let secondURLs = try makeTriptychFolders(in: base.appendingPathComponent("Second", isDirectory: true))
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        _ = try await registry.configureTriptych(
            id: UUID(),
            name: "Ethics",
            paperAnalysis: (firstURLs.analyses, UUID()),
            topicKnowledge: (firstURLs.topics, UUID()),
            output: (firstURLs.works, UUID())
        )
        _ = try await registry.configureTriptych(
            id: UUID(),
            name: "Ethics",
            paperAnalysis: (secondURLs.analyses, UUID()),
            topicKnowledge: (secondURLs.topics, UUID()),
            output: (secondURLs.works, UUID())
        )

        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.resolveTriptych("Ethics")
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
        let firstWorksID = UUID()
        let secondAnalysesID = UUID()
        let secondTopicsID = UUID()
        let secondWorksID = UUID()
        _ = try await registry.configureTriptych(
            id: firstID,
            paperAnalysis: (firstURLs.analyses, firstAnalysesID),
            topicKnowledge: (firstURLs.topics, UUID()),
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
            topicKnowledge: (replacementTopics, UUID()),
            output: (firstURLs.works, firstWorksID)
        )

        let second = try #require(await registry.triptych(id: secondID))
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
        #expect(await registry.triptych(id: oldTriptychID) == nil)
        #expect(await registry.defaultTriptych()?.id == stableTriptychID)
    }

    @Test("A damaged v2 registry is preserved and rejects mutation")
    func corruptRegistryFailsClosed() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let urls = try makeTriptychFolders(in: base.appendingPathComponent("Domain", isDirectory: true))
        let storage = base.appendingPathComponent("registry", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let registryURL = storage.appendingPathComponent("workspace-registry-v2.json")
        let damaged = Data("researcher recovery data, not valid JSON".utf8)
        try damaged.write(to: registryURL)
        let registry = WorkspaceRegistry(storageURL: storage)

        await #expect(throws: WorkspaceRegistryError.self) {
            try await registry.configureTriptych(
                paperAnalysis: (urls.analyses, UUID()),
                topicKnowledge: (urls.topics, UUID()),
                output: (urls.works, UUID())
            )
        }
        #expect(try Data(contentsOf: registryURL) == damaged)
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
        _ = try await registry.configureDefaultTriptych(
            paperAnalysis: (papers, UUID()),
            topicKnowledge: (topics, UUID()),
            output: (output, UUID())
        )

        let changed = try await registry.configureDefaultTriptych(
            paperAnalysis: (papers, UUID()),
            topicKnowledge: (newTopics, UUID()),
            output: (output, UUID())
        )

        #expect(changed.vault(for: .topicKnowledge)?.canonicalPath == newTopics.path)
        #expect(await registry.allVaults().filter { $0.role == .topicKnowledge }.count == 1)
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

    @Test("Workspace registration repairs IDs to match canonical vault identities")
    func threeVaultWorkspaceRepairsMismatchedIdentityIDs() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let papers = base.appendingPathComponent("papers", isDirectory: true)
        let topics = base.appendingPathComponent("topics", isDirectory: true)
        let output = base.appendingPathComponent("output", isDirectory: true)
        for url in [papers, topics, output] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let registry = WorkspaceRegistry(storageURL: base.appendingPathComponent("registry", isDirectory: true))
        _ = try await registry.configureDefaultTriptych(
            paperAnalysis: (papers, UUID()),
            topicKnowledge: (topics, UUID()),
            output: (output, UUID())
        )
        let repairedPaperID = UUID()
        let repairedTopicID = UUID()
        let repairedOutputID = UUID()

        let repaired = try await registry.configureDefaultTriptych(
            paperAnalysis: (papers, repairedPaperID),
            topicKnowledge: (topics, repairedTopicID),
            output: (output, repairedOutputID)
        )

        #expect(repaired.vault(for: .paperAnalysis)?.id == repairedPaperID)
        #expect(repaired.vault(for: .topicKnowledge)?.id == repairedTopicID)
        #expect(repaired.vault(for: .output)?.id == repairedOutputID)
        #expect(await registry.allVaults().filter { [repairedPaperID, repairedTopicID, repairedOutputID].contains($0.id) }.count == 3)
    }

    @Test("Vault identity can be restored by its stable ID")
    func vaultIdentityLookup() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let registry = VaultIdentityRegistry(applicationSupportURL: base)

        let registered = try await registry.identity(for: vault)
        let restored = await registry.identity(id: registered.id)

        #expect(restored?.id == registered.id)
        #expect(restored?.canonicalPath == registered.canonicalPath)
        #expect(await registry.identity(forCanonicalPath: vault.path)?.id == registered.id)
    }

    @Test("Reselecting a vault refreshes its bookmark without changing identity")
    func vaultIdentityBookmarkRefresh() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let registry = VaultIdentityRegistry(applicationSupportURL: base)

        let first = try await registry.identity(for: vault, bookmarkData: Data("first".utf8))
        let refreshed = try await registry.identity(for: vault, bookmarkData: Data("second".utf8))

        #expect(refreshed.id == first.id)
        #expect(refreshed.bookmarkData == Data("second".utf8))
        #expect(await registry.identity(id: first.id)?.bookmarkData == Data("second".utf8))
    }

    @Test("A corrupt vault identity registry is never replaced by a new registration")
    func corruptVaultIdentityRegistryFailsClosed() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let registryURL = base.appendingPathComponent("vault-registry.json")
        let corrupt = Data("{broken identity registry".utf8)
        try corrupt.write(to: registryURL)
        let registry = VaultIdentityRegistry(applicationSupportURL: base)

        #expect(await registry.healthError() != nil)
        await #expect(throws: VaultIdentityRegistryError.self) {
            _ = try await registry.identity(for: vault)
        }
        #expect(try Data(contentsOf: registryURL) == corrupt)
    }

    @Test("Portable control authorization is keyed by the folder containing Works")
    func portableControlAuthorizationPersists() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let container = base.appendingPathComponent("Triptych", isDirectory: true)
        let works = container.appendingPathComponent("Works", isDirectory: true)
        try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
        let registry = PortableControlAccessRegistry(applicationSupportURL: base)
        let bookmark = Data("synthetic security-scoped bookmark".utf8)

        let registered = try await registry.register(
            containerURL: container,
            bookmarkData: bookmark
        )
        let restored = await PortableControlAccessRegistry(
            applicationSupportURL: base
        ).access(forWorksURL: works)

        #expect(registered.canonicalContainerPath == container.path)
        #expect(restored?.canonicalContainerPath == container.path)
        #expect(restored?.bookmarkData == bookmark)
    }

    @Test("Portable control authorization rejects a folder other than the Works parent")
    func portableControlAuthorizationValidatesParent() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let expected = base.appendingPathComponent("Expected", isDirectory: true)
        let works = expected.appendingPathComponent("Works", isDirectory: true)
        let selected = base.appendingPathComponent("Selected", isDirectory: true)
        for url in [works, selected] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let registry = PortableControlAccessRegistry(applicationSupportURL: base)

        await #expect(throws: PortableControlAccessRegistryError.self) {
            _ = try await registry.register(containerURL: selected, forWorksURL: works)
        }
    }

    @Test("A corrupt portable control access registry is preserved")
    func corruptPortableControlAccessRegistryFailsClosed() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let registryURL = base.appendingPathComponent("portable-control-access.json")
        let corrupt = Data("{broken portable access registry".utf8)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try corrupt.write(to: registryURL)
        let registry = PortableControlAccessRegistry(applicationSupportURL: base)

        #expect(await registry.healthError() != nil)
        await #expect(throws: PortableControlAccessRegistryError.self) {
            _ = try await registry.register(
                containerURL: base,
                bookmarkData: Data("replacement".utf8)
            )
        }
        #expect(try Data(contentsOf: registryURL) == corrupt)
    }

}
