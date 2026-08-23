import Foundation
import Testing

@Suite("Research workflow interface proofs")
struct ResearchWorkflowPreviewCatalogTests {
    @Test("The catalog covers every retained research-workflow proof")
    func coversEveryRetainedProof() throws {
        let source = try previewSource()

        for proof in [
            "case actionSheet",
            "case researchGuidance",
            "case writeSetExtension",
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
        let guidanceStart = try #require(
            source.range(of: "// MARK: - Research Guidance")
        )
        let guidanceEnd = try #require(
            source.range(of: "// MARK: - Bounded write-set extension")
        )
        let guidanceSource = source[
            guidanceStart.lowerBound..<guidanceEnd.lowerBound
        ]

        for category in [
            "Skills",
            "Action Profiles",
            "Agent Access",
            "External Tools & Citations",
        ] {
            #expect(guidanceSource.contains(category))
        }

        for customization in [
            "one current Skill",
            "philosophical lenses",
            "Flat researcher-facing fields",
            "Ask Me Every Time",
            "Ask Me Only for Works",
            "Full Triptych Access",
            "APA 7",
            "Zotero Desktop local read-only API",
            "An Action Profile shapes academic inputs and results",
        ] {
            #expect(
                guidanceSource.contains(customization),
                "Missing Skill customization proof: \(customization)"
            )
        }

        for forbidden in [
            "Install Researcher Skill",
            "Installed Skills Start Disabled",
            "SKILL OVERRIDE",
            "PROFILE MODULES",
            "Reveal Skills Folder",
            "Skill recovery snapshots",
            "Research Activity",
            "Open Research Record",
            "case develop",
            "Revise",
            "Deny",
            " · ",
        ] {
            #expect(
                !guidanceSource.contains(forbidden),
                "Research Guidance exposes retired vocabulary: \(forbidden)"
            )
        }
    }

    @Test("The modular sheet cannot hide the app-owned authority boundary")
    func retainsAppOwnedBoundary() throws {
        let source = try previewSource()

        for field in [
            "Target",
            "Starting revision",
            "Agent access policy",
            "Candidate write scope",
            "Conflicts",
            "Recovery",
            "Conflict recovery",
        ] {
            #expect(source.contains(field), "Missing app-owned field: \(field)")
        }
        #expect(source.contains("Ask Me Every Time"))
        #expect(source.contains("Exact written Notes"))
        #expect(source.contains("Retained candidate source"))
        #expect(source.contains("Allow Selected Notes"))
        #expect(source.contains("Continue Without Additional Notes"))
        #expect(!source.contains("Cancel Request"))

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
