import Foundation
import Testing
import Yams
import ScholiumContracts
@testable import ScholiumCore

@Suite("Protected Skill catalog and Dialogue response contracts")
struct ResearchSkillCatalogTests {
    @Test("The bundled catalog loads official packages and their resources")
    func loadsCatalogAndResources() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        #expect(catalog.schemaVersion == ResearchSkillCatalog.currentSchemaVersion)
        #expect(catalog.schemaVersion == 3)
        #expect(catalog.entries.contains { $0.id == "scholium-core-protocol" })
        #expect(catalog.entries.contains { $0.id == "scholium-development" })
        #expect(catalog.entries.contains { $0.id == "scholium-manuscript" })
        #expect(catalog.entries.filter { $0.skillClass == .workflow }.map(\.id).sorted() == [
            "scholium-content-fidelity",
            "scholium-critique",
            "scholium-development",
            "scholium-manuscript",
            "scholium-revision",
        ])
        #expect(catalog.entries.contains {
            $0.id == "scholium-citation-verification"
                && $0.skillClass == .researcher
                && $0.role == "specialist"
                && $0.automaticModes.isEmpty
        })
        #expect(catalog.entries.contains {
            $0.id == "scholium-prose-control"
                && $0.skillClass == .researcher
                && $0.role == "specialist"
                && $0.automaticModes.isEmpty
        })
        #expect(catalog.entries.contains {
            $0.id == "scholium-source-analyzer"
                && $0.skillClass == .researcher
                && $0.role == "workflow"
                && $0.supportedFunctions.isEmpty
                && $0.supportedModes == [.analyze]
                && $0.automaticModes.isEmpty
        })
        let writing = try catalog.entry(id: "scholium-revision")
        let core = try catalog.entry(id: "scholium-core-protocol")
        let practices = try catalog.entry(id: "scholium-philosophical-practices")
        #expect(writing.compatiblePracticeIDs.contains("philosophical-expositor"))
        #expect(core.compatiblePracticeIDs.isEmpty)
        #expect(core.automaticModes == [.all])
        #expect(practices.practiceResources.count == 9)
        #expect(practices.practiceResources["reviewer"] == "references/Reviewer.md")
        for entry in catalog.entries {
            let source = try BundledResearchSkillLibrary.source(for: entry)
            #expect(!source.isEmpty)
        }
    }

    @Test("Source Analyzer is a complete agent method without a Research Function")
    func sourceAnalyzerIsExternalResearcherMethod() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let analyzer = try catalog.entry(id: "scholium-source-analyzer")

        #expect(analyzer.skillClass == .researcher)
        #expect(analyzer.role == "workflow")
        #expect(analyzer.updatePolicy == "copy-on-adoption-researcher-owned")
        #expect(analyzer.supportedFunctions.isEmpty)
        #expect(analyzer.supportedModes == [.analyze])
        #expect(analyzer.compatiblePracticeIDs == [
            "historical-interpreter",
            "conceptual-analyst",
            "argument-reconstructionist",
        ])
        #expect(analyzer.requiredSkillIDs == ["scholium-core-protocol"])
        #expect(try BundledResearchSkillLibrary.resourcePaths(for: analyzer) == [
            "SKILL.md",
            "references/analysis-forms.md",
            "references/bibliography-and-handoff.md",
            "references/method.md",
            "references/report-templates.md",
            "references/source-clusters.md",
        ])
    }

    @Test("The bundled resource mirror is byte-for-byte equal to canonical Skills")
    func canonicalResourceMirrorEquality() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let canonical = repositoryRoot.appendingPathComponent("Skills", isDirectory: true)
        let mirror = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills",
            isDirectory: true
        )

        let canonicalFiles = try regularFiles(relativeTo: canonical)
        let mirroredFiles = try regularFiles(relativeTo: mirror)

        #expect(canonicalFiles.keys.sorted() == mirroredFiles.keys.sorted())
        for relativePath in canonicalFiles.keys.sorted() {
            #expect(
                canonicalFiles[relativePath] == mirroredFiles[relativePath],
                "Bundled Skill mirror differs at \(relativePath)."
            )
        }
    }

    @Test("The APA starter remains an optional complete researcher package")
    func citationStarterIsResearcherOwnedAndBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let citation = try catalog.entry(id: "scholium-citation-verification")

        #expect(citation.skillClass == .researcher)
        #expect(citation.updatePolicy == "copy-on-adoption-researcher-owned")
        #expect(citation.supportedModes == [.audit])
        #expect(citation.supportedFunctions == [.fidelity])
        #expect(Set(citation.capabilities) == [.citationVerification, .citationFormatting])
        #expect(citation.citationStyles == ["apa-7"])
        #expect(
            citation.citationStyleResources["apa-7"]
                == "references/apa-7-starter.md"
        )
        #expect(citation.automaticModes.isEmpty)
        #expect(try BundledResearchSkillLibrary.resourcePaths(for: citation) == [
            "SKILL.md",
            "references/apa-7-starter.md",
            "references/verification-method.md",
        ])
    }

    @Test("Prose Control is a separate optional researcher-owned package")
    func proseControlIsResearcherOwnedAndBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let prose = try catalog.entry(id: "scholium-prose-control")

        #expect(prose.skillClass == .researcher)
        #expect(prose.role == "specialist")
        #expect(prose.updatePolicy == "copy-on-adoption-researcher-owned")
        #expect(prose.supportedModes == [.write])
        #expect(prose.automaticModes.isEmpty)
        #expect(prose.requiredSkillIDs == [
            "scholium-core-protocol",
            "scholium-revision",
        ])
        #expect(try BundledResearchSkillLibrary.resourcePaths(for: prose) == [
            "SKILL.md",
            "references/academic-prose-style.md",
        ])
    }

    @Test("Forward workflow cases reference valid packages, modes, and resources")
    func forwardWorkflowCasesRemainStructurallyRoutable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let casesURL = repositoryRoot
            .appendingPathComponent("Skills/evals/cases.yaml", isDirectory: false)
        let source = try String(contentsOf: casesURL, encoding: .utf8)
        let document = try #require(try Yams.load(yaml: source) as? [String: Any])
        #expect(document["schema_version"] as? Int == 2)
        #expect(document["status"] as? String == "forward-test-specification")

        let cases = try #require(document["cases"] as? [[String: Any]])
        #expect(cases.count >= 40)
        let catalog = try BundledResearchSkillLibrary.catalog()
        var seenIDs: Set<String> = []

        for workflowCase in cases {
            let id = try #require(workflowCase["id"] as? String)
            let request = try #require(workflowCase["request"] as? String)
            let invariants = try #require(workflowCase["invariants"] as? [String])
            #expect(seenIDs.insert(id).inserted)
            #expect(!request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!invariants.isEmpty)
            #expect(invariants.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })

            if let rawMode = workflowCase["expected_mode"] as? String {
                #expect(ResearchSkillMode(rawValue: rawMode) != nil)
            }

            if let primaryID = workflowCase["expected_primary"] as? String,
               primaryID.hasPrefix("scholium-") {
                _ = try catalog.entry(id: primaryID)
            }

            for (field, expectedClass) in [
                ("expected_system", ResearchSkillClass.system),
                ("expected_researcher", ResearchSkillClass.researcher),
            ] {
                for skillID in workflowCase[field] as? [String] ?? [] {
                    let entry = try catalog.entry(id: skillID)
                    #expect(entry.skillClass == expectedClass)
                }
            }

            for phase in workflowCase["expected_phases"] as? [String] ?? [] {
                if phase.hasPrefix("scholium-") {
                    _ = try catalog.entry(id: phase)
                } else {
                    #expect(
                        ResearchSkillMode(rawValue: phase) != nil
                            || ResearchFunctionID(rawValue: phase) != nil
                    )
                }
            }

            if let relativePath = workflowCase["expected_reference"] as? String {
                #expect(ResearchSkillResourcePath.isAllowed(relativePath))
                let primaryID = try #require(workflowCase["expected_primary"] as? String)
                let primary = try catalog.entry(id: primaryID)
                #expect(try BundledResearchSkillLibrary.resourcePaths(for: primary)
                    .contains(relativePath))
            }
        }
    }

    @Test("Catalog metadata cannot point across ownership roots or omit routing fields")
    func catalogRejectsUnsafeMetadata() {
        let unsafePath = ResearchSkillCatalogEntry(
            id: "scholium-safe",
            name: "Safe",
            description: "A test package.",
            skillClass: .system,
            role: "protocol",
            version: "1.0.0",
            supportedModes: [.all],
            updatePolicy: "release-managed-protected",
            resourcePath: "Scholium Workflow Skills/scholium-safe"
        )
        #expect(throws: ResearchSkillCatalogError.self) {
            _ = try ResearchSkillCatalog(entries: [unsafePath])
        }

        let missingModes = ResearchSkillCatalogEntry(
            id: "scholium-safe",
            name: "Safe",
            description: "A test package.",
            skillClass: .system,
            role: "protocol",
            version: "1.0.0",
            supportedModes: [],
            updatePolicy: "release-managed-protected",
            resourcePath: "Scholium System Skills/scholium-safe"
        )
        #expect(throws: ResearchSkillCatalogError.self) {
            _ = try ResearchSkillCatalog(entries: [missingModes])
        }
    }

    @Test("Selected package resources are bounded and explicitly retrievable")
    func selectedPackageResourcesAreBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let core = try catalog.entry(id: "scholium-core-protocol")
        let resources = try BundledResearchSkillLibrary.resourcePaths(for: core)
        #expect(resources.contains("SKILL.md"))
        #expect(resources.contains("references/mixed-mode.md"))
        #expect(!resources.contains { $0.contains("..") })
        #expect(!resources.contains { $0.hasPrefix("agents/") })
        #expect(try BundledResearchSkillLibrary.resource(
            for: core,
            relativePath: "references/mixed-mode.md"
        ).contains("Mixed"))
        #expect(throws: ResearchSkillCatalogError.self) {
            _ = try BundledResearchSkillLibrary.resource(
                for: core,
                relativePath: "../catalog.yaml"
            )
        }
    }

    @Test("Dialogue assembly is dependency closed and does not include unrelated workflows")
    func dialogueAssemblyIsSelective() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let ids = try catalog.dependencyClosedIDs(for: .dialogue)
        #expect(ids.contains("scholium-core-protocol"))
        #expect(ids.contains("scholium-research-integration"))
        #expect(ids.contains("scholium-dialogue-response"))
        #expect(!ids.contains("scholium-development"))
        #expect(!ids.contains("scholium-revision"))
    }

    @Test("Explicit workflow assembly includes only its dependency closure")
    func explicitWorkflowAssembly() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let ids = try catalog.dependencyClosedIDs(
            for: .develop,
            requestedSkillIDs: ["scholium-development"]
        )
        #expect(ids == ["scholium-core-protocol", "scholium-development"])
        #expect(!ids.contains("scholium-revision"))
    }

    @Test("System compatibility is separate from automatic activation")
    func optionalSystemAdaptersRemainSelectable() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()

        let ordinaryReview = try catalog.dependencyClosedIDs(for: .review)
        #expect(ordinaryReview == ["scholium-core-protocol"])

        let reviewWithDialogue = try catalog.dependencyClosedIDs(
            for: .review,
            requestedSkillIDs: ["scholium-dialogue-response"]
        )
        #expect(reviewWithDialogue.contains("scholium-core-protocol"))
        #expect(reviewWithDialogue.contains("scholium-research-integration"))
        #expect(reviewWithDialogue.contains("scholium-dialogue-response"))

        let analysisWithZotero = try catalog.dependencyClosedIDs(
            for: .develop,
            requestedSkillIDs: ["scholium-development", "scholium-zotero-integration"]
        )
        #expect(analysisWithZotero.contains("scholium-development"))
        #expect(analysisWithZotero.contains("scholium-zotero-integration"))

        let dialogue = try catalog.dependencyClosedIDs(for: .dialogue)
        #expect(dialogue == [
            "scholium-core-protocol",
            "scholium-research-integration",
            "scholium-dialogue-response",
        ])
    }

    @Test("Manuscript mode selects only the coordinator and its protected dependency")
    func manuscriptModeIsBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let ids = try catalog.dependencyClosedIDs(
            for: .manuscript,
            requestedSkillIDs: ["scholium-manuscript"]
        )
        #expect(ids == ["scholium-core-protocol", "scholium-manuscript"])
        #expect(!ids.contains("scholium-revision"))
        #expect(!ids.contains("scholium-critique"))
    }

    @Test("Mixed phases remain isolated while sharing only declared dependencies")
    func mixedPhasesAreIsolated() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let phases = try catalog.mixedDependencyClosedIDs([
            ResearchSkillAssemblyPhase(
                mode: .develop,
                skillIDs: ["scholium-development"]
            ),
            ResearchSkillAssemblyPhase(
                mode: .write,
                skillIDs: ["scholium-revision"]
            ),
        ])
        #expect(phases.count == 2)
        #expect(phases[0] == ["scholium-core-protocol", "scholium-development"])
        #expect(phases[1] == ["scholium-core-protocol", "scholium-revision"])
    }

    @Test("A Triptych-local package cannot shadow a protected package")
    func protectedPackageCollisionFailsClosed() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ResearchSkillStore(controlURL: root.appendingPathComponent(".scholium"))
        let shadow = root.appendingPathComponent(
            ".scholium/skills/scholium-core-protocol",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: shadow, withIntermediateDirectories: true)
        try Self.validSkillSource(name: "Shadow").write(
            to: shadow.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.instructionAssembly(mode: .dialogue)
        }
    }

    @Test("Dialogue response profile persists beside Works and snapshots independently")
    func profilePersistenceAndSnapshot() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let works = root.appendingPathComponent("Works", isDirectory: true)
        try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
        let control = TriptychControlStore(worksVaultURL: works)
        let vaultIDs = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
            ($0, UUID())
        })
        _ = try await control.bootstrap(vaultIDs: vaultIDs)

        let profile = DialogueResponseProfile(
            modules: [.criticalReflection, .remainingQuestions],
            commentPreservation: .keepAllComments
        )
        try await control.saveDialogueResponseProfile(profile)
        let loaded = try await control.dialogueResponseProfile()
        #expect(loaded.profileRevision == profile.profileRevision)
        #expect(abs(loaded.updatedAt.timeIntervalSince(profile.updatedAt)) < 1)
        #expect(loaded.base == profile.base)
        #expect(loaded.modules == profile.modules)
        #expect(loaded.concision == profile.concision)
        #expect(loaded.commentPreservation == profile.commentPreservation)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".scholium/dialogue-response.json").path
        ))

        let contract = DialogueResponseContract(profile: profile)
        let changed = profile.updated(
            modules: [DialogueResponseModule.researchDirections.rawValue]
        )
        #expect(contract.modules == profile.modules)
        #expect(changed.modules == ["research-directions"])
        #expect(contract.profileRevision == profile.profileRevision)
        #expect(changed.profileRevision != profile.profileRevision)
    }

    @Test("Dialogue transport exposes the exact concise request snapshot")
    func dialogueTransportSnapshot() {
        let dialogueID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let triptychID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let profile = DialogueResponseProfile(
            modules: [.criticalReflection, .philosophicalSignificance],
            commentPreservation: .keepAllComments
        )
        let locator = DialogueResponseTransport.locator(
            dialogueID: dialogueID,
            triptychID: triptychID,
            contract: DialogueResponseContract(profile: profile)
        )

        #expect(locator.contains("Dialogue ID: \(dialogueID.uuidString)"))
        #expect(locator.contains("Triptych selector: \(triptychID.uuidString)"))
        #expect(locator.contains("Response contract: request-snapshot"))
        #expect(locator.contains("Required base: academic-outcome"))
        #expect(locator.contains("Optional modules: critical-reflection, philosophical-significance"))
        #expect(locator.contains("Concision: concise"))
        #expect(locator.contains("Comment preservation: keep-all-comments"))
        #expect(locator.contains(
            "scholium dialogue show \(dialogueID.uuidString) --triptych \(triptychID.uuidString) --format json"
        ))
    }

    @Test("Dialogue entries decode without a legacy response snapshot")
    func legacyDialogueEntryDecodesWithoutContract() throws {
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Inspect this note.",
            selectedNotes: [],
            includedComments: [],
            generatedPrompt: "",
            checkpointID: UUID()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        #expect(!String(decoding: data, as: UTF8.self).contains("responseContract"))
        let decoded = try JSONDecoder.scholium.decode(DialogueEntry.self, from: data)
        #expect(decoded.responseContract == nil)
    }

    private static func validSkillSource(name: String) -> String {
        """
        ---
        name: \(name)
        description: A test-only package.
        ---
        Keep the test package bounded.
        """
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScholiumSkillCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func regularFiles(relativeTo root: URL) throws -> [String: Data] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var files: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            let relativePath = String(url.path.dropFirst(root.path.count + 1))
            files[relativePath] = try Data(contentsOf: url)
        }
        return files
    }
}

private extension JSONDecoder {
    static var scholium: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
