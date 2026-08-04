import Foundation
import Testing

@Suite("Research workflow interface proofs")
struct ResearchWorkflowPreviewCatalogTests {
    @Test("The catalog covers every retained research-workflow proof")
    func coversEveryRetainedProof() throws {
        let source = try previewSource()

        for proof in [
            "case actionSheet",
            "case skillInstaller",
            "case skillSettings",
            "case changeRequest",
        ] {
            #expect(source.contains(proof), "Missing interface proof: \(proof)")
        }

        for removedParallelProof in [
            "ResearchRecordsWindowProof",
            "ResearchRecordTwoColumnProof",
            "ResearchRecommendationTwoColumnProof",
        ] {
            #expect(!source.contains(removedParallelProof))
        }
    }

    @Test("Research Guidance proofs use the current researcher-governed vocabulary")
    func usesCurrentResearchGuidanceVocabulary() throws {
        let source = try previewSource()

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

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
