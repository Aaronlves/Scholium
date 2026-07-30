import Foundation
import Testing
import Yams
import ScholiumContracts
@testable import ScholiumCore

@Suite("Protected Skill catalog and bundled Method contracts")
struct ResearchSkillCatalogTests {
    @Test("The bundled catalog loads official packages and their resources")
    func loadsCatalogAndResources() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        #expect(catalog.schemaVersion == ResearchSkillCatalog.currentSchemaVersion)
        #expect(catalog.schemaVersion == 4)
        #expect(catalog.entries.contains { $0.id == "scholium-core-protocol" })
        #expect(catalog.entries.contains { $0.id == "scholium-analyze" })
        #expect(catalog.entries.contains { $0.id == "scholium-synthesize" })
        #expect(catalog.entries.contains { $0.id == "scholium-manuscript" })
        #expect(catalog.entries.filter { $0.skillClass == .method }.map(\.id).sorted() == [
            "scholium-analyze",
            "scholium-content-fidelity",
            "scholium-critique",
            "scholium-discuss",
            "scholium-manuscript",
            "scholium-synthesize",
            "scholium-write",
        ])
        #expect(catalog.entries.filter { $0.skillClass == .method }.allSatisfy {
            $0.supportedActions.count == 1 && $0.role == "method"
        })
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
                && $0.role == "method"
                && $0.supportedFunctions.isEmpty
                && $0.supportedModes == [.analyze]
                && $0.automaticModes.isEmpty
        })
        let writing = try catalog.entry(id: "scholium-write")
        let core = try catalog.entry(id: "scholium-core-protocol")
        let practices = try catalog.entry(id: "scholium-philosophical-practices")
        #expect(writing.compatiblePracticeIDs.contains("philosophical-expositor"))
        #expect(core.compatiblePracticeIDs.isEmpty)
        #expect(core.automaticModes == [.all])
        #expect(practices.practiceResources.count == 9)
        #expect(practices.practiceResources["reviewer"] == "references/Reviewer.md")
        #expect(practices.supportedModes.contains(.analyze))
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
        #expect(analyzer.role == "method")
        #expect(analyzer.updatePolicy == "copy-on-adoption-researcher-owned")
        #expect(analyzer.supportedFunctions.isEmpty)
        #expect(analyzer.supportedActions.isEmpty)
        #expect(analyzer.supportedModes == [.analyze])
        #expect(analyzer.capabilities == [.bibliographyRecommendation])
        #expect(analyzer.compatiblePracticeIDs == [
            "historical-interpreter",
            "conceptual-analyst",
            "argument-reconstructionist",
        ])
        #expect(analyzer.requiredSkillIDs == ["scholium-core-protocol"])
        #expect(try BundledResearchSkillLibrary.resourcePaths(for: analyzer) == [
            "SKILL.md",
            "references/analysis-forms.md",
            "references/bibliography-recommendations.md",
            "references/later-use-handoffs.md",
            "references/method.md",
            "references/report-templates.md",
            "references/source-clusters.md",
            "templates/recommended-bibliography-completion.json",
        ])
    }

    @Test("The bundled resource tree is the sole repository product Skill authority")
    func bundledResourcesAreCanonical() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let retiredMirrorSource = repositoryRoot.appendingPathComponent(
            "Skills",
            isDirectory: true
        )
        let canonical = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills",
            isDirectory: true
        )

        #expect(!FileManager.default.fileExists(atPath: retiredMirrorSource.path))
        let canonicalFiles = try regularFiles(relativeTo: canonical)
        #expect(canonicalFiles["catalog.yaml"] != nil)
        #expect(canonicalFiles["README.md"] != nil)
        #expect(canonicalFiles.keys.contains { $0.hasSuffix("/SKILL.md") })
        #expect(!canonicalFiles.keys.contains {
            $0.hasPrefix("Scholium Workflow Skills/")
        })
    }

    @Test("Every product Skill follows the bounded Agent Skills entry contract")
    func productSkillsFollowEntryContract() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let retiredModeInstruction = "select" + "_resources"
        for entry in catalog.entries {
            let source = try BundledResearchSkillLibrary.source(for: entry)
            let lines = source.components(separatedBy: .newlines)
            #expect(lines.count < 500)
            #expect(lines.first == "---")
            let closing = try #require(lines.dropFirst().firstIndex(of: "---"))
            let metadata = try #require(
                try Yams.load(yaml: lines[1..<closing].joined(separator: "\n"))
                    as? [String: Any]
            )
            #expect(metadata["name"] as? String == entry.id)
            let description = try #require(metadata["description"] as? String)
            #expect(!description.isEmpty)
            #expect(description.utf8.count <= 1_024)
            #expect(try BundledResearchSkillLibrary.resourcePaths(for: entry).allSatisfy(
                ResearchSkillResourcePath.isAllowed
            ))
            for path in try BundledResearchSkillLibrary.resourcePaths(for: entry) {
                let resource = try BundledResearchSkillLibrary.resource(
                    for: entry,
                    relativePath: path
                )
                #expect(!resource.contains(retiredModeInstruction))
            }
        }
    }

    @Test("The APA starter remains an optional complete researcher package")
    func citationStarterIsResearcherOwnedAndBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let citation = try catalog.entry(id: "scholium-citation-verification")

        #expect(citation.skillClass == .researcher)
        #expect(citation.updatePolicy == "copy-on-adoption-researcher-owned")
        #expect(citation.supportedModes == [.audit])
        #expect(citation.supportedActions == [.checkFidelity])
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
            "scholium-write",
        ])
        #expect(try BundledResearchSkillLibrary.resourcePaths(for: prose) == [
            "SKILL.md",
            "references/academic-prose-style.md",
        ])
    }

    @Test("Forward Action cases reference valid methods, modes, routes, and resources")
    func forwardWorkflowCasesRemainStructurallyRoutable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let casesURL = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills/evals/cases.yaml",
            isDirectory: false
        )
        let source = try String(contentsOf: casesURL, encoding: .utf8)
        let document = try #require(try Yams.load(yaml: source) as? [String: Any])
        #expect(document["schema_version"] as? Int == 3)
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

            var resolvedMode: ResearchSkillMode?
            if let rawMode = workflowCase["expected_mode"] as? String {
                resolvedMode = ResearchSkillMode(rawValue: rawMode)
                #expect(resolvedMode != nil)
            }

            let actionID = (workflowCase["expected_action"] as? String)
                .flatMap(ResearchActionID.init(rawValue:))
            if workflowCase["expected_action"] != nil {
                #expect(actionID != nil)
            }
            let expectedFunction = (workflowCase["expected_function"] as? String)
                .flatMap(ResearchFunctionID.init(rawValue:))
            if workflowCase["expected_function"] != nil {
                #expect(expectedFunction != nil)
            }

            if let primaryID = workflowCase["expected_primary"] as? String,
               primaryID.hasPrefix("scholium-") {
                let primary = try catalog.entry(id: primaryID)
                if primary.skillClass == .method, let actionID {
                    #expect(primary.supports(actionID))
                }
                if primary.skillClass == .method, let expectedFunction {
                    #expect(primary.supports(expectedFunction))
                }
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

            if let resolvedMode, resolvedMode != .mixed {
                let system = workflowCase["expected_system"] as? [String] ?? []
                let researcher = workflowCase["expected_researcher"] as? [String] ?? []
                let primary = (workflowCase["expected_primary"] as? String).map { [$0] } ?? []
                let requested = Array(Set((primary + system + researcher).filter {
                    $0.hasPrefix("scholium-")
                })).sorted()
                let assembled = try catalog.dependencyClosedIDs(
                    for: resolvedMode,
                    requestedSkillIDs: requested
                )
                #expect(requested.allSatisfy(assembled.contains))
            }

            for phase in workflowCase["expected_route"] as? [String] ?? [] {
                #expect(ResearchActionID(rawValue: phase) != nil)
            }

            if let relativePath = workflowCase["expected_reference"] as? String {
                #expect(ResearchSkillResourcePath.isAllowed(relativePath))
                let primaryID = try #require(workflowCase["expected_primary"] as? String)
                let primary = try catalog.entry(id: primaryID)
                #expect(try BundledResearchSkillLibrary.resourcePaths(for: primary)
                    .contains(relativePath))
            }
        }
        #expect(seenIDs.contains("source-route-complete"))
        #expect(seenIDs.contains("argument-route-complete"))
        #expect(seenIDs.contains("analyze-source-unavailable"))
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
            resourcePath: "Scholium Method Skills/scholium-safe"
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

        let missingAction = ResearchSkillCatalogEntry(
            id: "scholium-safe",
            name: "Safe",
            description: "A test Method package.",
            skillClass: .method,
            role: "method",
            version: "1.0.0",
            supportedFunctions: [.develop],
            supportedModes: [.analyze],
            updatePolicy: "release-managed-duplicable",
            resourcePath: "Scholium Method Skills/scholium-safe"
        )
        #expect(throws: ResearchSkillCatalogError.self) {
            _ = try ResearchSkillCatalog(entries: [missingAction])
        }

        let multipleFunctions = ResearchSkillCatalogEntry(
            id: "scholium-safe",
            name: "Safe",
            description: "A test Method package.",
            skillClass: .method,
            role: "method",
            version: "1.0.0",
            supportedActions: [.analyze],
            supportedFunctions: [.develop, .revise],
            supportedModes: [.analyze],
            updatePolicy: "release-managed-duplicable",
            resourcePath: "Scholium Method Skills/scholium-safe"
        )
        #expect(throws: ResearchSkillCatalogError.self) {
            _ = try ResearchSkillCatalog(entries: [multipleFunctions])
        }
    }

    @Test("Selected package resources are bounded and explicitly retrievable")
    func selectedPackageResourcesAreBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let core = try catalog.entry(id: "scholium-core-protocol")
        let resources = try BundledResearchSkillLibrary.resourcePaths(for: core)
        #expect(resources.contains("SKILL.md"))
        #expect(resources.contains("references/agent-transport.md"))
        #expect(resources.contains("references/mixed-mode.md"))
        #expect(!resources.contains { $0.contains("..") })
        #expect(!resources.contains { $0.hasPrefix("agents/") })
        let coreEntry = try BundledResearchSkillLibrary.resource(
            for: core,
            relativePath: "SKILL.md"
        )
        for protectedCapacity in [
            "Effective authority is the intersection",
            "Do not infer the researcher's belief, intention",
            "Do not transmit Works content to another service",
            "Scholium-owned records may contain only",
            "A Skill may declare a need. It cannot grant itself access",
        ] {
            #expect(coreEntry.contains(protectedCapacity))
        }
        #expect(coreEntry.contains("references/agent-transport.md"))
        #expect(!coreEntry.contains("scholium skills catalog"))
        #expect(!coreEntry.contains("scholium doctor"))
        let transport = try BundledResearchSkillLibrary.resource(
            for: core,
            relativePath: "references/agent-transport.md"
        )
        #expect(transport.contains("scholium doctor --format json"))
        #expect(transport.contains(
            "scholium skills catalog --triptych <triptych> --format text"
        ))
        #expect(transport.contains(
            "scholium skills show <method-skill-id> --triptych <triptych> --format text"
        ))
        #expect(transport.contains(
            "--resource <relative-path> --format text"
        ))
        #expect(transport.contains("Prepared Action state and typed `nextActions` remain JSON"))
        #expect(!transport.contains(
            "scholium skills catalog --triptych <triptych> --format json"
        ))
        #expect(try BundledResearchSkillLibrary.resource(
            for: core,
            relativePath: "references/mixed-mode.md"
        ).contains("Mixed"))

        let critique = try catalog.entry(id: "scholium-critique")
        let critiqueMethod = try BundledResearchSkillLibrary.resource(
            for: critique,
            relativePath: "references/method.md"
        )
        for requirement in [
            "Overall Assessment",
            "Materials Consulted and Limitations",
            "exact Work identity and starting fingerprint",
            "original line",
            "short quotation",
            "Traced, Untraced, Disputed, or Beyond Sources",
        ] {
            #expect(critiqueMethod.contains(requirement))
        }
        #expect(throws: ResearchSkillCatalogError.self) {
            _ = try BundledResearchSkillLibrary.resource(
                for: core,
                relativePath: "../catalog.yaml"
            )
        }
    }

    @Test("Discuss assembly keeps protected mechanics separate from its ordinary Method")
    func discussAssemblyIsSelective() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let ids = try catalog.dependencyClosedIDs(for: .discuss)
        #expect(ids.contains("scholium-core-protocol"))
        #expect(ids.contains("scholium-research-integration"))
        #expect(ids.contains("scholium-discussion-protocol"))
        #expect(!ids.contains("scholium-discuss"))
        #expect(!ids.contains("scholium-analyze"))

        let withMethod = try catalog.dependencyClosedIDs(
            for: .discuss,
            requestedSkillIDs: ["scholium-discuss"]
        )
        #expect(withMethod.contains("scholium-discuss"))
    }

    @Test("Unsupported Dialogue mode is rejected instead of projected as Discuss")
    func legacyDialogueModeIsRejected() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ResearchSkillMode.self,
                from: Data("\"dialogue\"".utf8)
            )
        }
    }

    @Test("Explicit Analyze assembly includes only its Method dependency closure")
    func explicitAnalyzeAssembly() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let ids = try catalog.dependencyClosedIDs(
            for: .analyze,
            requestedSkillIDs: ["scholium-analyze"]
        )
        #expect(ids == [
            "scholium-core-protocol",
            "scholium-research-integration",
            "scholium-analyze",
        ])
        #expect(!ids.contains("scholium-synthesize"))
        #expect(!ids.contains("scholium-write"))
    }

    @Test("System compatibility is separate from automatic activation")
    func optionalSystemAdaptersRemainSelectable() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()

        let ordinaryReview = try catalog.dependencyClosedIDs(for: .review)
        #expect(ordinaryReview == ["scholium-core-protocol"])

        let reviewWithMethod = try catalog.dependencyClosedIDs(
            for: .review,
            requestedSkillIDs: ["scholium-critique"]
        )
        #expect(reviewWithMethod.contains("scholium-core-protocol"))
        #expect(reviewWithMethod.contains("scholium-research-integration"))
        #expect(reviewWithMethod.contains("scholium-critique"))

        let analysisWithZotero = try catalog.dependencyClosedIDs(
            for: .analyze,
            requestedSkillIDs: ["scholium-analyze", "scholium-zotero-integration"]
        )
        #expect(analysisWithZotero.contains("scholium-analyze"))
        #expect(analysisWithZotero.contains("scholium-zotero-integration"))

        let discussion = try catalog.dependencyClosedIDs(for: .discuss)
        #expect(discussion == [
            "scholium-core-protocol",
            "scholium-research-integration",
            "scholium-discussion-protocol",
        ])
    }

    @Test("Manuscript mode selects only the coordinator and its protected dependency")
    func manuscriptModeIsBounded() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let ids = try catalog.dependencyClosedIDs(
            for: .manuscript,
            requestedSkillIDs: ["scholium-manuscript"]
        )
        #expect(ids == [
            "scholium-core-protocol",
            "scholium-research-integration",
            "scholium-manuscript",
        ])
        #expect(!ids.contains("scholium-write"))
        #expect(!ids.contains("scholium-critique"))
    }

    @Test("Mixed phases remain isolated while sharing only declared dependencies")
    func mixedPhasesAreIsolated() throws {
        let catalog = try BundledResearchSkillLibrary.catalog()
        let phases = try catalog.mixedDependencyClosedIDs([
            ResearchSkillAssemblyPhase(
                mode: .analyze,
                skillIDs: ["scholium-analyze"]
            ),
            ResearchSkillAssemblyPhase(
                mode: .write,
                skillIDs: ["scholium-write"]
            ),
        ])
        #expect(phases.count == 2)
        #expect(phases[0] == [
            "scholium-core-protocol",
            "scholium-research-integration",
            "scholium-analyze",
        ])
        #expect(phases[1] == [
            "scholium-core-protocol",
            "scholium-research-integration",
            "scholium-write",
        ])
    }

    @Test("A Triptych-local package cannot shadow a protected package")
    func protectedPackageCollisionFailsClosed() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ResearchSkillTransactionCoordinator(controlURL: root.appendingPathComponent(".scholium"))
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
            _ = try await store.instructionAssembly(mode: .discuss)
        }
    }

    @Test("Discuss response contract freezes one request snapshot")
    func profileSnapshot() {
        let profile = DialogueResponseProfile(
            modules: [.criticalReflection, .remainingQuestions],
            commentPreservation: .keepAllComments
        )
        let contract = DialogueResponseContract(profile: profile)
        let changed = profile.updated(
            modules: [DialogueResponseModule.researchDirections.rawValue]
        )
        #expect(contract.modules == profile.modules)
        #expect(changed.modules == ["research-directions"])
        #expect(contract.profileRevision == profile.profileRevision)
        #expect(changed.profileRevision != profile.profileRevision)
    }

    @Test("Discuss transport exposes the exact concise request snapshot")
    func discussTransportSnapshot() {
        let discussionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let triptychID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let profile = DialogueResponseProfile(
            modules: [.criticalReflection, .philosophicalSignificance],
            commentPreservation: .keepAllComments
        )
        let locator = DiscussResponseTransport.locator(
            discussionID: discussionID,
            triptychID: triptychID,
            contract: DialogueResponseContract(profile: profile)
        )

        #expect(locator.contains("Discussion ID: \(discussionID.uuidString)"))
        #expect(locator.contains("Triptych selector: \(triptychID.uuidString)"))
        #expect(locator.contains("Response contract: request-snapshot"))
        #expect(locator.contains("Required base: academic-outcome"))
        #expect(locator.contains("Optional modules: critical-reflection, philosophical-significance"))
        #expect(locator.contains("Concision: concise"))
        #expect(locator.contains("Comment preservation: keep-all-comments"))
        #expect(locator.contains(
            "scholium discuss show \(discussionID.uuidString) --triptych \(triptychID.uuidString) --format json"
        ))
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
