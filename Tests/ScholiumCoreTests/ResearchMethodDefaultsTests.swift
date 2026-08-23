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
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "skill-folders/analyze/references/method-fit.md"
        ).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "skill-folders/write/references/genre-and-revision.md"
        ).path))
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
            "`agent finish-discussion`",
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

    @Test("Advanced research guidance stays pluralist, bounded, and non-certifying")
    func advancedResearchGuidanceBoundaries() throws {
        let analyze = try #require(BundledResearchMethodDefaults.definitions.first {
            $0.actionID == .analyze
        })
        #expect(analyze.resources.contains("references/method-fit.md"))
        let methodFit = String(
            decoding: try BundledResearchSkillResources.data(
                directory: analyze.resourceDirectory,
                relativePath: "references/method-fit.md"
            ),
            as: UTF8.self
        )
        #expect(methodFit.contains("universal default"))
        #expect(methodFit.contains("comparative weakness"))
        #expect(methodFit.contains("Historical or exegetical"))
        #expect(methodFit.contains("Empirically informed or interdisciplinary"))
        #expect(methodFit.contains("**Genealogical:**"))
        #expect(methodFit.contains("**Critical or diagnostic:**"))
        #expect(methodFit.contains("**Normative:**"))
        #expect(methodFit.contains("**Reflective equilibrium:**"))
        #expect(methodFit.contains("Do not require reflective-equilibrium"))
        #expect(methodFit.contains(
            "source-stated consequences separate from agent-derived implications"
        ))
        #expect(methodFit.contains("does not certify"))
        let analyzeMethod = String(
            decoding: try BundledResearchSkillResources.data(
                directory: analyze.resourceDirectory,
                relativePath: "references/method.md"
            ),
            as: UTF8.self
        )
        #expect(analyzeMethod.contains("requested depth, intended use"))
        #expect(analyzeMethod.contains("must not override a"))
        #expect(analyzeMethod.contains("requested thorough analysis"))
        #expect(analyzeMethod.contains("printed pagination, PDF pagination"))
        #expect(analyzeMethod.contains("self-positioning as verified field history"))

        let synthesize = try #require(BundledResearchMethodDefaults.definitions.first {
            $0.actionID == .synthesize
        })
        let synthesisMethod = String(
            decoding: try BundledResearchSkillResources.data(
                directory: synthesize.resourceDirectory,
                relativePath: "references/method.md"
            ),
            as: UTF8.self
        )
        #expect(synthesisMethod.contains("practical cutoff"))
        #expect(synthesisMethod.contains("provisionally saturated"))
        #expect(synthesisMethod.contains("Apply this step only when"))
        #expect(synthesisMethod.contains("do not infer a stopping state"))
        #expect(synthesisMethod.contains("**not assessed:**"))
        #expect(synthesisMethod.contains("**insufficient basis:**"))
        #expect(synthesisMethod.contains("Without inspected change history"))
        #expect(synthesisMethod.contains("Never infer complete literature coverage"))

        let critique = try BundledResearchMethodDefaults.primarySource(for: .critique)
        #expect(critique.contains("For passage scope"))
        #expect(critique.contains("never certifies originality, publishability, doctoral level"))

        let write = try #require(BundledResearchMethodDefaults.definitions.first {
            $0.actionID == .write
        })
        #expect(write.resources.contains("references/genre-and-revision.md"))
        let genreAndRevision = String(
            decoding: try BundledResearchSkillResources.data(
                directory: write.resourceDirectory,
                relativePath: "references/genre-and-revision.md"
            ),
            as: UTF8.self
        )
        #expect(genreAndRevision.contains("Route by philosophical function"))
        #expect(genreAndRevision.contains("Revise in philosophical priority order"))
        #expect(genreAndRevision.contains("Do not silently propagate the change"))
        #expect(genreAndRevision.contains("illustrative rather than exhaustive"))
        #expect(genreAndRevision.contains("**Genealogical, critical, or diagnostic:**"))
        #expect(genreAndRevision.contains("**Comparative or cross-tradition:**"))
        let writeMethod = String(
            decoding: try BundledResearchSkillResources.data(
                directory: write.resourceDirectory,
                relativePath: "references/method.md"
            ),
            as: UTF8.self
        )
        #expect(writeMethod.contains("Sustain the Work's philosophical purpose"))
        #expect(writeMethod.contains("Only when the Work itself claims"))
        #expect(writeMethod.contains("need not manufacture a"))
        let feedback = String(
            decoding: try BundledResearchSkillResources.data(
                directory: write.resourceDirectory,
                relativePath: "references/feedback.md"
            ),
            as: UTF8.self
        )
        #expect(feedback.contains("human reader or a prior Critique"))
        #expect(feedback.contains("do not use it to generate new independent"))
        #expect(feedback.contains("not applicable"))
        #expect(feedback.contains("concession or residual risk"))

        let fidelity = try #require(BundledResearchMethodDefaults.definitions.first {
            $0.actionID == .checkFidelity
        })
        let contentFidelity = String(
            decoding: try BundledResearchSkillResources.data(
                directory: fidelity.resourceDirectory,
                relativePath: "references/content.md"
            ),
            as: UTF8.self
        )
        #expect(contentFidelity.contains("Calibrate by claim type"))
        #expect(contentFidelity.contains("publication readiness, workflow status"))
        #expect(contentFidelity.contains("exact wording and authorship"))
        #expect(contentFidelity.contains("Settle, authorization, selection, or silence"))
        #expect(contentFidelity.contains("researcher-authored wording without inferred"))
        #expect(contentFidelity.contains("researcher-stated commitment"))

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let explorer = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumCore/Resources/Skills/Philosophical Practices/Research-Explorer.md"
            ),
            encoding: .utf8
        )
        #expect(explorer.contains("field-supported"))
        #expect(!explorer.contains("field-verified"))
        #expect(explorer.contains("blocked-or-stuck"))
        #expect(explorer.contains("empty result set"))
        #expect(explorer.contains("not-assessed"))
        #expect(explorer.contains("insufficient-basis"))
        #expect(explorer.contains("actual sequence of additions"))
        let conceptualAnalyst = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumCore/Resources/Skills/Philosophical Practices/Conceptual-Analyst.md"
            ),
            encoding: .utf8
        )
        #expect(conceptualAnalyst.contains("Change-impact map"))
        #expect(conceptualAnalyst.contains("authorization to rewrite every"))
        #expect(conceptualAnalyst.contains("biconditional"))
        let argumentReconstructionist = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumCore/Resources/Skills/Philosophical Practices/Argument-Reconstructionist.md"
            ),
            encoding: .utf8
        )
        #expect(argumentReconstructionist.contains("formal or semi-formal work"))
        #expect(argumentReconstructionist.contains("for normative work"))
        #expect(argumentReconstructionist.contains("for cases and thought experiments"))

        for source in [
            analyzeMethod,
            genreAndRevision,
            writeMethod,
            feedback,
            contentFidelity,
            conceptualAnalyst,
            argumentReconstructionist,
        ] {
            #expect(!source.contains("Philosophical Reports"))
            #expect(!source.contains("Dissertation Vault"))
            #expect(!source.contains("Hongqing"))
        }

        let resourceRoot = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills",
            isDirectory: true
        )
        let resourceEnumerator = try #require(FileManager.default.enumerator(
            at: resourceRoot,
            includingPropertiesForKeys: nil
        ))
        var checkedMarkdownResources = 0
        for case let url as URL in resourceEnumerator where url.pathExtension == "md" {
            checkedMarkdownResources += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for privateMarker in [
                "Philosophical Reports",
                "Dissertation Vault",
                "Hongqing",
                "WORKSPACE_ROOT",
                "advisor-ready",
                "committee-ready",
                "submission-ready",
            ] {
                #expect(!source.contains(privateMarker))
            }
        }
        #expect(checkedMarkdownResources > 0)
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
