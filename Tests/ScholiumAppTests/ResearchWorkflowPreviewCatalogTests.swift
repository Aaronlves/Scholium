import Foundation
import Testing

@Suite("Research workflow interface proofs")
struct ResearchWorkflowPreviewCatalogTests {
    @Test("The catalog covers every Session 7 proof and deterministic state")
    func coversEveryProofAndState() throws {
        let source = try previewSource()

        for proof in [
            "case actions",
            "case actionSheet",
            "case skillInstaller",
            "case skillSettings",
            "case changeRequest",
            "case researchRecord",
            "case stateMatrix",
        ] {
            #expect(source.contains(proof), "Missing interface proof: \(proof)")
        }

        for state in [
            "case empty",
            "case loading",
            "case error",
            "case conflict",
            "case permissionInvalid",
        ] {
            #expect(source.contains(state), "Missing deterministic state: \(state)")
        }

        #expect(source.contains("ResearchRecordTwoColumnProof"))
        #expect(source.contains("ResearchRecordUtilityProof"))
        #expect(!source.contains("ResearchRecordStackedProof"))
        let utilityRecordProof = try #require(
            source.components(separatedBy: "private struct ResearchRecordUtilityProof")
                .dropFirst()
                .first?
                .components(separatedBy: "private struct ResearchRecordTwoColumnProof")
                .first
        )
        #expect(!utilityRecordProof.contains("GeometryReader"))
        #expect(utilityRecordProof.contains("Fixed 760 × 680 utility window"))
        #expect(!source.contains(".listStyle(.sidebar)"))
        #expect(!source.contains("Show Narrow Fallback"))
        #expect(source.contains("#Preview(\"Research Record Fixed Utility\")"))
        #expect(source.contains(".frame(width: 760, height: 680)"))
        #expect(source.contains("Fidelity could not be completed for this recorded revision."))
        #expect(source.contains("Agent-reported Materials used"))
        #expect(source.contains("researcherSkillProofFixtures.filter"))
        #expect(source.contains("$0.isEnabled && $0.showsInActions"))
        #expect(source.contains("counterexampleStressTestFixture.applicableRoles"))
        #expect(source.contains("ScholiumApparatusSection(\"RESEARCH\")"))
        #expect(source.contains("ScholiumApparatusSection(\"REVIEW\")"))
        #expect(source.contains("ScholiumApparatusSection(\"RESEARCHER SKILLS\")"))
        #expect(source.contains("ScholiumApparatusSection(\"JUDGMENT\")"))
    }

    @Test("Actions and settings use the frozen researcher-governed vocabulary")
    func usesFrozenVocabulary() throws {
        let source = try previewSource()

        #expect(
            try actionTitles(in: source, after: "case .analysis:", before: "case .topic:")
                == ["Discuss", "Analyze", "Check Fidelity"]
        )
        #expect(
            try actionTitles(in: source, after: "case .topic:", before: "case .work:")
                == ["Discuss", "Synthesize", "Check Fidelity"]
        )
        #expect(
            try actionTitles(
                in: source,
                after: "case .work:",
                before: "private struct ResearchActionProofItem"
            ) == ["Discuss", "Write", "Critique", "Check Fidelity"]
        )

        for category in [
            "Methods",
            "Researcher Skills",
            "Permissions",
            "Sources & Integrations",
            "Recovery & Technical",
        ] {
            #expect(source.contains(category))
        }

        for customization in [
            "Triptych",
            "Note roles",
            "Show in Actions",
            "Order in Actions",
            "PROFILE MODULES",
            "Required authorization",
            "Standing policy",
            "Ask Me Every Time",
            "Ask Me Only for Works",
            "Triptych-wide",
            "Disable",
            "Replace…",
            "Restore Bundled Reference",
        ] {
            #expect(source.contains(customization), "Missing Skill customization proof: \(customization)")
        }

        let systemSkillSection = try #require(
            source.components(separatedBy: "ResearchSkillGroup(title: \"SYSTEM SKILLS\"")
                .dropFirst()
                .first?
                .components(separatedBy: "ResearchSkillGroup(title: \"BUNDLED REFERENCES\"")
                .first
        )
        #expect(systemSkillSection.contains("actionTitle: nil"))

        for forbidden in [
            "Research Activity",
            "Open Research Record",
            "Develop",
            "Revise",
            "Deny",
            " · ",
        ] {
            #expect(!source.contains(forbidden), "Preview exposes retired vocabulary: \(forbidden)")
        }
    }

    @Test("The modular sheet cannot hide the app-owned authority boundary")
    func retainsAppOwnedBoundary() throws {
        let source = try previewSource()

        for field in [
            "Target",
            "Starting revision",
            "Permission",
            "Candidate write scope",
            "Conflicts",
            "Recovery",
            "Conflict recovery",
        ] {
            #expect(source.contains(field), "Missing app-owned field: \(field)")
        }
        #expect(source.contains("Ask Me Every Time"))
        #expect(source.contains("Exact written Notes"))
        #expect(source.contains("Retained displaced bytes"))
        #expect(source.contains("Installed Skills Start Disabled"))
        #expect(source.contains("Allow These Notes Once"))
        #expect(source.contains("Continue Without Changes"))
        #expect(source.contains("Cancel the Run"))

        for recordField in [
            "Pinned",
            "Date",
            "Skill",
            "Action",
            "Participant",
        ] {
            #expect(source.contains(recordField), "Missing Research Record field: \(recordField)")
        }
        #expect(!source.contains("action: \"Discussion\""))
        #expect(source.contains("values: [\"Any Action\", \"Discuss\""))
    }

    @Test("Appearance and accessibility review entry points remain explicit")
    func exposesAppearanceAndAccessibilityEntries() throws {
        let source = try previewSource()

        #expect(source.contains("Workflow Dark"))
        #expect(source.contains(".init(increasedContrast: true)"))
        #expect(source.contains(".init(reduceTransparency: true)"))
        #expect(source.contains(".init(reduceMotion: true)"))
        #expect(source.contains("Workflow 200% Legibility"))
        #expect(source.contains(".dynamicTypeSize(.accessibility2)"))
        #expect(source.contains(".accessibilityAddTraits(.isHeader)"))
        #expect(source.contains(".accessibilityIdentifier(\"scholium.proofs.catalog\")"))

        for forbiddenSurface in [
            ".regularMaterial",
            ".ultraThinMaterial",
            "glassEffect(",
            "GlassEffectContainer",
            ".buttonStyle(.glass",
        ] {
            #expect(!source.contains(forbiddenSurface))
        }
    }

    @Test("The runnable catalog is QA-bounded and remains suppressed by default")
    func qaRouteIsBounded() throws {
        let repository = repositoryRoot()
        let appSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )

        #expect(appSource.contains("#if DEBUG\n        Window("))
        #expect(appSource.contains("id: \"scholium-research-workflow-proofs\""))
        #expect(appSource.contains(".defaultLaunchBehavior(.suppressed)"))
        #expect(appSource.contains("Bundle.main.bundleIdentifier == \"com.scholium.qa\""))
        #expect(appSource.contains("--scholium-research-workflow-proofs"))
        #expect(appSource.contains("openWindow(id: \"scholium-research-workflow-proofs\")"))
    }

    private func previewSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Scholium/UI/PreviewCatalog/ResearchWorkflowPreviewCatalog.swift"
            ),
            encoding: .utf8
        )
    }

    private func actionTitles(
        in source: String,
        after start: String,
        before end: String
    ) throws -> [String] {
        let section = try #require(
            source.components(separatedBy: start)
                .dropFirst()
                .first?
                .components(separatedBy: end)
                .first
        )
        let expression = try NSRegularExpression(
            pattern: #"\.init\(id: \"[^\"]+\", title: \"([^\"]+)\""#
        )
        let range = NSRange(section.startIndex ..< section.endIndex, in: section)
        return expression.matches(in: section, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: section) else { return nil }
            return String(section[capture])
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
