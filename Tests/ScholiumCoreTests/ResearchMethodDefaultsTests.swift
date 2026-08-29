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

    @Test("Default bootstrap creates registrations and routed philosophical lens references")
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
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "practices"
        ).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "skill-folders/analyze/references/method-fit.md"
        ).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "skill-folders/write/references/genre-and-revision.md"
        ).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "skill-folders/analyze/references/Argument-Reconstructionist.md"
        ).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "skill-folders/critique/references/Reviewer.md"
        ).path))
    }

    @Test("Project discovery exposes every System Skill and enabled Method")
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
        #expect(initial.skills.count == 9)
        #expect(initial.skills.first?.name == "scholium-core-protocol")
        #expect(Set(initial.skills.filter { $0.ownership == .scholiumManaged }
            .map(\.name)) == Set(ResearchSystemSkillID.allCases.map(\.rawValue)))
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
        #expect(afterExternal.skills.first(where: { $0.actionID == .analyze })?
            .sourceDirectory == externalFolder.resolvingSymlinksInPath().path)
        #expect(afterExternal.skills.allSatisfy {
            $0.sourceDirectory != machine.resolvingSymlinksInPath().path
        })
    }

    @Test("Project discovery rejects a folder whose SKILL entry is not the registered Method")
    func projectSkillDiscoveryRejectsSubstitutedEntry() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-skill-substitution-\(UUID().uuidString)",
            isDirectory: true
        )
        let control = workspace.appendingPathComponent(".scholium", isDirectory: true)
        let machine = workspace.appendingPathComponent("machine", isDirectory: true)
        let folder = workspace.appendingPathComponent("external", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(
            at: control,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let primary = folder.appendingPathComponent("SKILL.md")
        let substituted = workspace.appendingPathComponent("substituted-SKILL.md")
        let registeredSource = """
        ---
        name: scholium-analyze
        description: Registered Analyze
        ---
        # Registered
        """
        try registeredSource.write(to: primary, atomically: true, encoding: .utf8)
        try """
        ---
        name: scholium-analyze
        description: Substituted Analyze
        ---
        # Substituted
        """.write(
            to: substituted,
            atomically: true,
            encoding: .utf8
        )

        let store = ResearchConfigurationStore(
            controlURL: control,
            triptychID: UUID(),
            machineStorageURL: machine
        )
        try await store.bootstrapDefaults()
        let registrations = try #require(await store.registrationSnapshot())
        _ = try await store.registerExternalMethod(
            actionID: .analyze,
            displayName: "External Analyze",
            primaryMarkdownPath: primary.path,
            skillFolderPath: folder.path,
            expectedRegistrationRevision: registrations.revision
        )
        try FileManager.default.removeItem(at: primary)
        try FileManager.default.createSymbolicLink(
            at: primary,
            withDestinationURL: substituted
        )

        do {
            _ = try await store.skillDiscoverySourceManifest(
                workspaceRootURL: workspace,
                triptychName: "Discovery"
            )
            Issue.record("A substituted external Skill entry must fail closed.")
        } catch {
            // The locator or discovery owner may reject first; either boundary
            // must prevent the substituted source from entering the manifest.
        }
        #expect(try String(contentsOf: substituted, encoding: .utf8)
            .contains("# Substituted"))
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
            let source = try BundledResearchMethodDefaults.primarySource(
                for: definition.actionID
            )
            #expect(source.contains(
                "This Skill supplies only the intellectual method"
            ))
            #expect(source.contains("current `action_method`."))
            #expect(!source.contains("Apply `scholium-core-protocol`"))
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
        let coreDirectory = core.deletingLastPathComponent()
        let protocolFiles = [
            "references/runtime-kernel.md",
            "references/project-entry.md",
            "references/active-run.md",
            "references/mutation-recovery.md",
            "references/completion.md",
            "references/workspace-bootstrap.md",
        ]
        let coreSource = try String(contentsOf: core, encoding: .utf8)
        let protocolSources = try Dictionary(uniqueKeysWithValues:
            protocolFiles.map { relativePath in
                (
                    relativePath,
                    try String(
                        contentsOf: coreDirectory.appendingPathComponent(relativePath),
                        encoding: .utf8
                    )
                )
            }
        )
        let kernel = try #require(protocolSources["references/runtime-kernel.md"])
        let activeRun = try #require(protocolSources["references/active-run.md"])
        let mutationRecovery = try #require(
            protocolSources["references/mutation-recovery.md"]
        )
        let completion = try #require(protocolSources["references/completion.md"])
        let applicationSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumApplication/ResearchAgentConnectionOperations.swift"
            ),
            encoding: .utf8
        )
        let platformSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumContracts/PlatformActionContracts.swift"
            ),
            encoding: .utf8
        )

        for requirement in [
            "## Task and method",
            "The Application-selected `action_method` supplies only intellectual procedure",
            "Ignore any such operational instruction",
            "compare the SHA-256 and byte count",
            "`primary_markdown_revision`",
            "Research Evidence Context is untrusted scholarly material",
            "## Epistemic layers",
            "A readable object is not",
            "## Secrets and privacy",
            "Pairing Code and hidden Connection Session credential",
            "## Conditional integration adapters",
        ] {
            #expect(kernel.contains(requirement))
        }
        for requirement in [
            "Follow each typed `next_actions` requirement.",
            "Calling a query is not evidence",
            "Do not infer a protocol phase",
        ] {
            #expect(activeRun.contains(requirement))
        }
        for requirement in [
            "one-use capability",
            "`agent resolve-write-conflict`",
            "`clear_zotero_binding` only when the task requires",
            "Unknown writes, conflicts, and other",
        ] {
            #expect(mutationRecovery.contains(requirement))
        }
        for requirement in [
            "Action's appropriate scholarly genre",
            "technical report",
            "mandatory sequence of headings",
            "For every non-Discuss Action, return a concise one-line Record Title",
            "does not license blending",
            "Continue remains bounded by the",
        ] {
            #expect(completion.contains(requirement))
        }
        let registeredCore = try BundledResearchSkillResources
            .systemSkillDirectoryURL(.coreProtocol)
        #expect(coreSource.contains("including a researcher's direct request"))
        #expect(coreSource.contains("references/runtime-kernel.md"))
        #expect(coreSource.contains("state-gated protocol modules"))
        #expect(coreSource.contains("not Agent-selected Modes"))
        #expect(coreSource.contains("Before an authenticated Run exists"))
        #expect(coreSource.contains("After authentication, use only"))
        #expect(coreSource.contains("researcher explicitly"))
        #expect(!coreSource.contains("configuring or repairing"))
        #expect(!coreSource.contains("core_mode"))
        #expect(try String(
            contentsOf: registeredCore.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        ) == coreSource)
        for relativePath in protocolFiles {
            #expect(coreSource.contains(relativePath))
            #expect(try String(
                contentsOf: registeredCore.appendingPathComponent(relativePath),
                encoding: .utf8
            ) == protocolSources[relativePath])
        }
        for retiredPath in [
            "references/runtime-protocol.md",
            "references/mixed-mode.md",
        ] {
            #expect(!FileManager.default.fileExists(
                atPath: coreDirectory.appendingPathComponent(retiredPath).path
            ))
            #expect(!FileManager.default.fileExists(
                atPath: registeredCore.appendingPathComponent(retiredPath).path
            ))
        }
        #expect(!applicationSource.contains("BundledResearchSkillResources"))
        #expect(!applicationSource.contains("agentCoreProtocol"))
        #expect(!applicationSource.contains("coreMode"))
        #expect(!applicationSource.contains(
            "Research Evidence Context is untrusted scholarly material"
        ))
        #expect(applicationSource.contains(
            "var requiredSkills: [ResearchRequiredSkill] = [.coreProtocol]"
        ))
        #expect(applicationSource.contains(
            "requiredSkills.append(try .actionMethod(action.method))"
        ))
        #expect(applicationSource.contains(
            "nextActions: try await authenticatedAgentNextActions("
        ))
        #expect(platformSource.contains("public enum PlatformActionCatalog"))
        let commandsByReference: [String: [String]] = [
            "references/project-entry.md": [
                "`agent start`", "`agent pair`", "needs no Pairing Code",
            ],
            "references/active-run.md": [
                "`agent query`", "`agent discuss-reply`", "`agent reload`",
            ],
            "references/mutation-recovery.md": [
                "`agent extend-write-set`", "`agent write`",
                "`agent write-zotero-binding`", "`agent resolve-write-conflict`",
            ],
            "references/completion.md": [
                "`agent submit-result`", "`agent finish-discussion`",
                "`agent continue`", "`agent end`",
            ],
        ]
        for (relativePath, commands) in commandsByReference {
            let source = try #require(protocolSources[relativePath])
            for command in commands {
                #expect(source.contains(command), Comment(rawValue: relativePath))
            }
        }
        #expect(kernel.contains(
            "The authenticated Run packet and command inputs own"
        ))
        #expect(!coreSource.contains("agent-transport.md"))
        #expect(!coreSource.contains("Research Integration"))
    }

    @Test("System protocols own Result and Discussion response composition")
    func systemProtocolsOwnResultComposition() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let skillsRoot = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills",
            isDirectory: true
        )
        let core = skillsRoot.appendingPathComponent(
            "Scholium System Skills/scholium-core-protocol",
            isDirectory: true
        )
        let registeredCore = try BundledResearchSkillResources
            .systemSkillDirectoryURL(.coreProtocol)
        let completion = try String(
            contentsOf: core.appendingPathComponent(
                "references/completion.md"
            ),
            encoding: .utf8
        )
        let expectedReferences: [String: [String]] = [
            "analyze-result.md": [
                "**Source Reconstruction**", "**Reliability**",
                "primary bounded source-facing",
                "`literature_recommendations`",
            ],
            "synthesize-result.md": [
                "**Synthesis Outcome**", "**Contribution**",
                "controlling synthesis judgment",
            ],
            "write-result.md": [
                "**Writing Outcome**", "**Change Kind**",
                "resulting Work now accomplishes",
            ],
            "critique-result.md": [
                "**Assessment**", "**Issue Kind**", "controlling judgment",
            ],
            "check-fidelity-result.md": [
                "academic_results.values", "fidelity_outcomes",
                "No-inconsistency-found",
            ],
            "discuss-result.md": ["scholium-discussion-protocol", "no generic"],
        ]
        for (file, markers) in expectedReferences {
            #expect(completion.contains("references/\(file)"))
            let source = try String(
                contentsOf: core.appendingPathComponent("references/\(file)"),
                encoding: .utf8
            )
            for marker in markers {
                #expect(source.contains(marker), Comment(rawValue: file))
            }
            #expect(try String(
                contentsOf: registeredCore.appendingPathComponent("references/\(file)"),
                encoding: .utf8
            ) == source)
        }
        let methodOwnedPhrases: [String: String] = [
            "analyze-result.md": "compact thematic account for a philosopher",
            "synthesize-result.md": "problem-centered result",
            "write-result.md": "editing diary",
            "critique-result.md": "coherent scholarly assessment",
            "check-fidelity-result.md": "claim and material philosophical defect",
        ]
        for (file, phrase) in methodOwnedPhrases {
            let source = try String(
                contentsOf: core.appendingPathComponent("references/\(file)"),
                encoding: .utf8
            )
            #expect(!source.contains(phrase), Comment(rawValue: file))
        }

        for definition in BundledResearchMethodDefaults.definitions {
            let source = try BundledResearchMethodDefaults.primarySource(
                for: definition.actionID
            )
            #expect(!source.contains("## Feedback"))
            #expect(!source.contains("academic_results"))
            #expect(!source.contains("fidelity_outcomes"))
            #expect(!source.contains("scholium agent"))
            #expect(!source.contains("next_actions"))
            #expect(!source.contains("submit-result"))
            #expect(!source.contains("If no authenticated Run exists"))
            #expect(source.contains("## Scholarly outcome"))
        }

        let outcomeMarkers: [ResearchActionID: [String]] = [
            .discuss: [
                "coherent contribution to the live inquiry",
                "rather than a questionnaire",
            ],
            .analyze: [
                "thematic piece of philosophical analysis",
                "not a technical",
            ],
            .synthesize: [
                "problem-centered philosophical synthesis",
                "not a Material",
            ],
            .write: [
                "prose native to the Work's philosophical genre",
                "Do not insert a change log",
            ],
            .critique: [
                "coherent scholarly assessment",
                "not eight independent mini-reports",
            ],
            .checkFidelity: [
                "claim-centered philosophical accuracy judgment",
                "not a verification",
            ],
        ]
        for (actionID, markers) in outcomeMarkers {
            let source = try BundledResearchMethodDefaults.primarySource(
                for: actionID
            )
            for marker in markers {
                #expect(source.contains(marker), Comment(rawValue: actionID.rawValue))
            }
        }

        let discussMethod = skillsRoot.appendingPathComponent(
            "Scholium Method Skills/scholium-discuss",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(
            atPath: discussMethod.appendingPathComponent(
                "references/response-contract.md"
            ).path
        ))
        let discussionSystem = skillsRoot.appendingPathComponent(
            "Scholium System Skills/scholium-discussion-protocol",
            isDirectory: true
        )
        #expect(FileManager.default.fileExists(
            atPath: discussionSystem.appendingPathComponent(
                "references/response-contract.md"
            ).path
        ))
        let discussionResponse = try String(
            contentsOf: discussionSystem.appendingPathComponent(
                "references/response-contract.md"
            ),
            encoding: .utf8
        )
        #expect(discussionResponse.contains(
            "one coherent philosophical response"
        ))
        #expect(discussionResponse.contains("not mandatory headings"))
    }

    @Test("The registered Zotero Skill retains its protected capability contract")
    func zoteroIntegrationSkillResources() throws {
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
        let registered = try BundledResearchSkillResources
            .systemSkillDirectoryURL(.zoteroIntegration)
        #expect(try String(
            contentsOf: registered.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        ) == expectedSkill)
        #expect(try String(
            contentsOf: registered.appendingPathComponent("references/mcp-contract.md"),
            encoding: .utf8
        ) == expectedContract)
        #expect(expectedSkill.contains("installed CLI help"))
        #expect(expectedContract.contains(
            "installed MCP tool schemas own current tool names"
        ))
        #expect(!expectedSkill.contains("scholium zotero mcp serve"))
        #expect(!expectedContract.contains("zotero_status"))
    }

    @Test("Analyze Method keeps source method while Core owns Result composition")
    func analyzeMethodSupportsExternalZoteroSource() throws {
        let analyze = try #require(
            BundledResearchMethodDefaults.definitions.first {
                $0.actionID == .analyze
            }
        )
        let source = try BundledResearchMethodDefaults.primarySource(for: .analyze)
        let method = String(
            decoding: try BundledResearchSkillResources.data(
                directory: analyze.resourceDirectory,
                relativePath: "references/method.md"
            ),
            as: UTF8.self
        )
        let core = try BundledResearchSkillResources
            .systemSkillDirectoryURL(.coreProtocol)
        let composition = try String(
            contentsOf: core.appendingPathComponent(
                "references/analyze-result.md"
            ),
            encoding: .utf8
        )
        #expect(source.contains("independent Zotero/MCP capability"))
        #expect(!source.contains("fidelity_outcomes"))
        #expect(!source.contains("academic Result fields"))
        #expect(composition.contains("`fidelity_outcomes`"))
        #expect(composition.contains("researcher-initiated Check Fidelity Run"))
        #expect(composition.contains("**Reliability**"))
        #expect(source.contains("## Scholarly outcome"))
        #expect(source.contains("not a technical"))
        #expect(source.contains("## Relation to researcher Works"))
        #expect(source.contains("load-bearing premises or grounds"))
        #expect(source.contains("Never infer relevance or agreement"))
        #expect(method.contains("govern inquiry and verification"))
        #expect(method.contains("not an output"))
        #expect(method.contains("source-specific headings"))
        #expect(method.contains("mark the first transition from reconstruction"))
        #expect(method.contains("Do not rely on the Research Record's field structure"))
        #expect(composition.contains("primary bounded source-facing"))
        #expect(composition.contains("`literature_recommendations`"))
        #expect(!composition.contains("literatureRecommendations"))
        #expect(composition.contains("Compare every populated field"))
        #expect(composition.contains("recommended work itself was not inspected"))
        #expect(composition.contains("without naming a provider"))
        #expect(composition.contains("Do not mention tools, commands"))
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
                "ScholiumCore/Resources/Skills/Scholium Method Skills/scholium-analyze/references/Research-Explorer.md"
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
                "ScholiumCore/Resources/Skills/Scholium Method Skills/scholium-analyze/references/Conceptual-Analyst.md"
            ),
            encoding: .utf8
        )
        #expect(conceptualAnalyst.contains("Change-impact map"))
        #expect(conceptualAnalyst.contains("authorization to rewrite every"))
        #expect(conceptualAnalyst.contains("biconditional"))
        #expect(conceptualAnalyst.contains("same target, competing accounts"))
        #expect(conceptualAnalyst.contains("converting labels into options"))
        let conceptualDefinitions = BundledResearchMethodDefaults.definitions.filter {
            $0.resources.contains("references/Conceptual-Analyst.md")
        }
        #expect(conceptualDefinitions.count == 5)
        for definition in conceptualDefinitions {
            let copy = String(
                decoding: try BundledResearchSkillResources.data(
                    directory: definition.resourceDirectory,
                    relativePath: "references/Conceptual-Analyst.md"
                ),
                as: UTF8.self
            )
            #expect(copy == conceptualAnalyst)
        }
        let argumentReconstructionist = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumCore/Resources/Skills/Scholium Method Skills/scholium-analyze/references/Argument-Reconstructionist.md"
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

    @Test("Research Action quality QA starts clean and keeps its reviewer rubric isolated")
    func researchActionQualityFixtureIsClean() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent(
            "Tools/Fixtures/research-action-quality-v1",
            isDirectory: true
        )
        for relativePath in ["01-analyses", "02-topics", "03-works"] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(
                atPath: fixture.appendingPathComponent(relativePath).path,
                isDirectory: &isDirectory
            ))
            #expect(isDirectory.boolValue)
        }
        #expect(!FileManager.default.fileExists(
            atPath: fixture.appendingPathComponent(".scholium").path
        ))

        let performer = try String(
            contentsOf: fixture.appendingPathComponent("performer-case.md"),
            encoding: .utf8
        )
        let reviewer = try String(
            contentsOf: fixture.appendingPathComponent("reviewer-rubric.md"),
            encoding: .utf8
        )
        #expect(performer.contains("## Raw researcher request template"))
        #expect(performer.contains("No private researcher vault"))
        #expect(!performer.contains("## Hard gates"))
        #expect(reviewer.contains("## Hard gates"))
        #expect(reviewer.contains("Give this rubric only to a fresh reviewer"))
        #expect(reviewer.contains("different accounts of it, or genuine alternatives"))
        #expect(reviewer.contains("tool narration"))

        let builder = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Tools/Scripts/build-qa-app.sh"
            ),
            encoding: .utf8
        )
        let qualityBuilder = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Tools/Scripts/build-research-action-quality-qa.sh"
            ),
            encoding: .utf8
        )
        #expect(builder.contains("SCHOLIUM_QA_REQUIRE_CLEAN_RESEARCH_STATE"))
        #expect(builder.contains("must not contain portable .scholium state"))
        #expect(qualityBuilder.contains("research-action-quality-v1"))
        #expect(qualityBuilder.contains("SCHOLIUM_QA_REQUIRE_CLEAN_RESEARCH_STATE=1"))
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
        for retiredPath in [
            "scholium-core-protocol/references/runtime-protocol.md",
            "scholium-core-protocol/references/mixed-mode.md",
        ] {
            #expect(!FileManager.default.fileExists(
                atPath: systemSkills.appendingPathComponent(retiredPath).path
            ))
        }
        for path in [
            "ScholiumCore/WorkspaceBootstrap.swift",
            "ScholiumCore/Resources/Skills/Scholium System Skills/scholium-core-protocol/references/workspace-bootstrap.md",
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
