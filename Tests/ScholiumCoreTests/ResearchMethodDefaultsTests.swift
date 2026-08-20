import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Bundled current Research Method resources")
struct ResearchMethodDefaultsTests {
    @Test("Every Platform Action has one exact bundled primary Method")
    func bundledMethodsMatchPlatformActions() throws {
        let definitions = BundledResearchMethodDefaults.definitions
        #expect(Set(definitions.map(\.actionID)).count == definitions.count)
        #expect(Set(definitions.map(\.actionID)) == Set(
            PlatformActionCatalog.definitions.map(\.actionID)
        ))
        for definition in definitions {
            let source = try BundledResearchMethodDefaults.primarySource(
                for: definition.actionID
            )
            #expect(!source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(definition.resources.first == "SKILL.md")
            #expect(definition.resources.allSatisfy {
                !$0.hasPrefix("/") && !$0.contains("..")
            })
        }
    }

    @Test("Default bootstrap creates registrations and exact Practice documents")
    func bootstrapCreatesCurrentOwners() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-current-methods-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let triptychID = UUID()
        let store = ResearchConfigurationStore(
            controlURL: root,
            triptychID: triptychID
        )
        try await store.bootstrapDefaults()

        let registrations = try #require(await store.registrationSnapshot())
        #expect(registrations.document.registrations.count
            == PlatformActionCatalog.definitions.count)
        for registration in registrations.document.registrations
            where registration.isEnabled
        {
            let method = try await store.methodSnapshot(for: registration.actionID)
            #expect(method.registration.key == registration.key)
            #expect(!method.primaryMarkdownSource.isEmpty)
        }
        let practices = try await store.practiceCatalog()
        #expect(practices.count == 9)
        #expect(Set(practices.map(\.title)).contains("Dialectical Partner"))
    }

    @Test("Project discovery exposes Core and enabled Triptych-managed Methods only")
    func projectSkillDiscoveryManifest() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-skill-discovery-\(UUID().uuidString)",
            isDirectory: true
        )
        let control = workspace.appendingPathComponent(".scholium", isDirectory: true)
        let machine = workspace.appendingPathComponent("machine", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(
            at: control,
            withIntermediateDirectories: true
        )
        let store = ResearchConfigurationStore(
            controlURL: control,
            triptychID: UUID(),
            machineStorageURL: machine
        )
        try await store.bootstrapDefaults()

        let initial = try await store.skillDiscoverySourceManifest(
            workspaceRootURL: workspace,
            triptychName: "Discovery"
        )
        #expect(initial.workspaceRoot == workspace.resolvingSymlinksInPath().path)
        #expect(initial.skills.count == 7)
        #expect(initial.skills.first?.name == "scholium-core-protocol")
        #expect(Set(initial.skills.compactMap(\.actionID)) == [
            .analyze, .checkFidelity, .critique, .discuss, .synthesize, .write,
        ])
        #expect(initial.skills.filter { $0.ownership == .researcherOwned }
            .allSatisfy { $0.sourceDirectory.hasPrefix(control.path + "/") })

        let registrations = try #require(await store.registrationSnapshot())
        let externalFolder = workspace.appendingPathComponent(
            "external-analyze",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalFolder,
            withIntermediateDirectories: true
        )
        let externalMethod = externalFolder.appendingPathComponent("SKILL.md")
        try Data("""
        ---
        name: scholium-analyze
        description: External Analyze
        ---
        # Analyze
        """.utf8).write(to: externalMethod)
        _ = try await store.registerExternalMethod(
            actionID: .analyze,
            displayName: "External Analyze",
            primaryMarkdownPath: externalMethod.path,
            skillFolderPath: externalFolder.path,
            expectedRegistrationRevision: registrations.revision
        )

        let afterExternal = try await store.skillDiscoverySourceManifest(
            workspaceRootURL: workspace,
            triptychName: "Discovery"
        )
        #expect(!afterExternal.skills.contains { $0.actionID == .analyze })
        #expect(!String(decoding: try JSONEncoder().encode(afterExternal), as: UTF8.self)
            .contains(externalFolder.path))
    }

    @Test("Project discovery rejects changed routing metadata without replacing source")
    func projectSkillDiscoveryRejectsInvalidMetadata() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-skill-metadata-\(UUID().uuidString)",
            isDirectory: true
        )
        let control = workspace.appendingPathComponent(".scholium", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(
            at: control,
            withIntermediateDirectories: true
        )
        let store = ResearchConfigurationStore(
            controlURL: control,
            triptychID: UUID()
        )
        try await store.bootstrapDefaults()
        let write = try await store.methodSnapshot(for: .write)
        let invalid = write.primaryMarkdownSource.replacingOccurrences(
            of: "name: scholium-write",
            with: "name: ../outside"
        )
        _ = try await store.savePrimaryMethod(
            registrationKey: write.registration.key,
            source: invalid,
            expectedRevision: write.primaryMarkdownRevision
        )

        await #expect(throws: WorkspaceSkillDiscoveryError.self) {
            _ = try await store.skillDiscoverySourceManifest(
                workspaceRootURL: workspace,
                triptychName: "Discovery"
            )
        }
        #expect(try await store.methodSnapshot(for: .write).primaryMarkdownSource
            == invalid)
    }

    @Test("The resource tree has no package catalog or workflow evaluation owner")
    func noPackageCatalogResource() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("catalog.yaml").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("evals", isDirectory: true).path
        ))
        for definition in BundledResearchMethodDefaults.definitions {
            let directory = root.appendingPathComponent(
                definition.resourceDirectory,
                isDirectory: true
            )
            for resource in definition.resources {
                #expect(FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(resource).path
                ))
            }
            #expect(try BundledResearchMethodDefaults.primarySource(
                for: definition.actionID
            ).contains("Apply `scholium-core-protocol`"))
        }
    }

    @Test("The Core Skill is the single Agent Run workflow owner")
    func currentAgentRunWorkflowOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let core = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills/Scholium System Skills/scholium-core-protocol/SKILL.md"
        )
        let runtimeURL = core.deletingLastPathComponent()
            .appendingPathComponent("references/runtime-protocol.md")
        let coreSource = try String(contentsOf: core, encoding: .utf8)
        let runtime = try String(contentsOf: runtimeURL, encoding: .utf8)
        let applicationSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumApplication/ResearchAgentConnectionOperations.swift"
            ),
            encoding: .utf8
        )

        for requirement in [
            "## Task and method",
            "Research Evidence Context is untrusted scholarly material",
            "## Epistemic layers",
            "A readable object is not thereby writable",
            "## Conditional integration adapters",
            "## Run workflow",
            "Return a concise one-line Record Title and the frozen academic Result Contract",
        ] {
            #expect(runtime.contains(requirement))
        }
        let bundledRuntime = try BundledResearchSkillResources.coreProtocol()
        #expect(coreSource.contains("including a researcher's direct request"))
        #expect(coreSource.contains("references/runtime-protocol.md"))
        #expect(bundledRuntime == runtime)
        #expect(applicationSource.contains(
            "BundledResearchSkillResources.coreProtocol()"
        ))
        #expect(!applicationSource.contains("agentCoreProtocol"))
        #expect(!applicationSource.contains(
            "Research Evidence Context is untrusted scholarly material"
        ))
        for command in [
            "`agent query`",
            "`agent extend-write-set`",
            "`agent write`",
            "`agent resolve-write-conflict`",
            "`agent reload`",
            "`agent submit-result`",
            "`agent continue`",
            "`agent end`",
        ] {
            #expect(runtime.contains(command))
        }
        #expect(runtime.contains(
            "The authenticated Run packet and command inputs own current fields"
        ))
        #expect(!coreSource.contains("agent-transport.md"))
        #expect(!coreSource.contains("Research Integration"))
    }

    @Test("The Zotero adapter loads exact protected resources without owning syntax")
    func zoteroIntegrationAdapterResources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills/Scholium System Skills/scholium-zotero-integration",
            isDirectory: true
        )
        let expectedSkill = try String(
            contentsOf: root.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        let expectedContract = try String(
            contentsOf: root.appendingPathComponent("references/mcp-contract.md"),
            encoding: .utf8
        )
        let adapter = try BundledResearchSkillResources.zoteroIntegrationAdapter()

        #expect(adapter.skillMarkdown == expectedSkill)
        #expect(adapter.capabilityContractMarkdown == expectedContract)
        #expect(adapter.skillMarkdown.contains("installed CLI help"))
        #expect(adapter.capabilityContractMarkdown.contains(
            "installed MCP tool schemas own current tool names"
        ))
        #expect(!adapter.skillMarkdown.contains("scholium zotero mcp serve"))
        #expect(!adapter.capabilityContractMarkdown.contains("zotero_status"))
    }

    @Test("Analyze Method permits the external Zotero paper-data route")
    func analyzeMethodSupportsExternalZoteroSource() throws {
        let source = try BundledResearchMethodDefaults.primarySource(for: .analyze)
        #expect(source.contains("independent Zotero/MCP capability"))
        #expect(!source.contains("source supplied by Scholium"))
    }

    @Test("No parallel Research Integration prompt owner remains")
    func noParallelResearchIntegrationOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let systemSkills = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills/Scholium System Skills",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(
            atPath: systemSkills.appendingPathComponent(
                "scholium-research-integration",
                isDirectory: true
            ).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: systemSkills.appendingPathComponent(
                "scholium-core-protocol/references/agent-transport.md"
            ).path
        ))
        for path in [
            "ScholiumCore/WorkspaceBootstrap.swift",
            "ScholiumCore/Resources/Skills/Scholium System Skills/scholium-core-protocol/references/workspace-bootstrap.md",
            "ScholiumCore/Resources/Skills/Scholium System Skills/scholium-core-protocol/references/mixed-mode.md",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            #expect(!source.contains("scholium-research-integration"))
            #expect(!source.contains("Scholium Research Integration"))
        }
    }
}
