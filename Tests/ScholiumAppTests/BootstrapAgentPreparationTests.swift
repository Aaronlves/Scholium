import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Bootstrap Agent preparation")
struct BootstrapAgentPreparationTests {
    @Test("Bootstrap keeps a near-square initial window with a wider task pane")
    func bootstrapWindowMetrics() {
        #expect(ScholiumMetrics.Onboarding.preferredWidth == 760)
        #expect(ScholiumMetrics.Onboarding.preferredHeight == 740)
    }

    @Test("Welcome presents the README product position without the retired writing-room copy")
    func welcomeProductPosition() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSetupView.swift"
            ),
            encoding: .utf8
        )
        let tagline = "A local-first, document-authoritative research environment for philosophy and the humanities."
        let normalizedReadme = readme
            .replacingOccurrences(of: "\n> ", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        #expect(normalizedReadme.contains(tagline))
        #expect(source.contains(tagline))
        #expect(source.contains("remains the primary interface"))
        #expect(source.contains("A field of inquiry takes shape as a Triptych."))
        #expect(source.contains("Reading, writing, Search, Connections, review, and recovery work without an Agent."))
        #expect(!source.contains("A local-first writing room"))
        #expect(!source.contains("Hold the thread\\nof thought."))
    }

    @Test("Released Bootstrap artwork has only the four approved fixed tunings")
    func artworkConfigurations() {
        let welcome = BootstrapStageArtworkConfiguration.approved(for: .welcome)
        #expect(welcome.handStyle == "Point")
        #expect(welcome.handAssetName == "manicule-canonical")
        #expect(welcome.constellationPattern == "Flow")
        #expect(welcome.colorField == "Golden Ochre")
        #expect(welcome.offsetX == 0 && welcome.offsetY == 0)
        #expect(welcome.scale == 1 && welcome.rotation == 0)

        let triptych = BootstrapStageArtworkConfiguration.approved(for: .triptych)
        #expect(triptych.handStyle == "Offer")
        #expect(triptych.handAssetName == "manicule-offer-v2")
        #expect(triptych.constellationPattern == "Flow")
        #expect(triptych.colorField == "Mineral Blue")
        #expect(triptych.offsetX == -115 && triptych.offsetY == -180)
        #expect(triptych.scale == 1.18 && triptych.rotation == 78)

        let agent = BootstrapStageArtworkConfiguration.approved(for: .agent)
        #expect(agent.handStyle == "Unlock Straight")
        #expect(agent.handAssetName == "manicule-unlock-straight-v1")
        #expect(agent.constellationPattern == "Converge")
        #expect(agent.colorField == "Verdigris")
        #expect(agent.offsetX == 60 && agent.offsetY == 0)
        #expect(agent.scale == 1 && agent.rotation == 0)

        let ready = BootstrapStageArtworkConfiguration.approved(for: .ready)
        #expect(ready.handStyle == "Lift")
        #expect(ready.handAssetName == "manicule-lift-v1")
        #expect(ready.constellationPattern == "Converge")
        #expect(ready.colorField == "Oxblood")
        #expect(ready.offsetX == 24 && ready.offsetY == 57)
        #expect(ready.scale == 0.96 && ready.rotation == 0)

        for configuration in [welcome, triptych, agent, ready] {
            #expect(configuration.narrativeShapes == "Constellation")
            #expect(configuration.showsHand)
            #expect(!configuration.showsContactTarget)
            #expect(!configuration.showsSafeRegion)
        }
    }

    @Test("Setup prompt binds one exact project root and preserves the Run boundary")
    func promptContract() {
        let root = URL(
            fileURLWithPath: "/Users/researcher/Research/Emotional Fittingness",
            isDirectory: true
        )
        let prompt = BootstrapAgentPreparationPrompt.text(triptychRootURL: root)

        #expect(prompt.contains(
            "Project root and workspace root (use this exact same folder):\n"
                + root.path
        ))
        #expect(prompt.contains(ScholiumCLIDistribution.downloadURL))
        #expect(prompt.contains("You may install only these two release-owned items"))
        #expect(prompt.contains("Do not use sudo"))
        #expect(prompt.contains("Do not edit PATH, shell profiles, global Agent configuration, or macOS quarantine metadata"))
        #expect(prompt.contains("Ignore additional JSON fields"))
        #expect(prompt.contains("`product` is `Scholium`"))
        #expect(prompt.contains("`cli_version` is `\(ScholiumProductIdentity.marketingVersion)`"))
        #expect(prompt.contains("$HOME/.local/bin/scholium version --format json"))
        #expect(prompt.contains("$HOME/.local/bin/scholium doctor --format json"))
        #expect(prompt.contains("$HOME/.local/bin/scholium help agent"))
        #expect(prompt.contains("AGENTS.md"))
        #expect(prompt.contains("CLAUDE.md"))
        #expect(prompt.contains("scholium workspace skill-sources --format json"))
        #expect(prompt.contains("Accept only schema_version 1"))
        #expect(prompt.contains("Codex: .agents/skills"))
        #expect(prompt.contains("Claude Code: .claude/skills"))
        #expect(prompt.contains("real directory, not a symlink"))
        #expect(prompt.contains("resolved discovery directory to remain beneath"))
        #expect(prompt.contains("create one directory symlink"))
        #expect(prompt.contains("already a symlink to the same resolved source"))
        #expect(prompt.contains("Never overwrite, merge, rename, or repair it"))
        #expect(prompt.contains("scholium workspace bootstrap --triptych <triptych_id> --target <workspace_root>"))
        #expect(prompt.contains("Never overwrite, merge, shadow, or silently replace"))
        #expect(prompt.contains("Never edit .scholium directly"))
        #expect(prompt.contains("Do not read Triptych research files or request a pairing code now"))
        #expect(prompt.contains("A later researcher request may start an eligible Run"))
        #expect(prompt.contains("current host's own Skill listing"))
        #expect(prompt.contains("do not claim Ready yet"))
    }

    @Test("The app exposes no CLI installation or machine-status owner")
    func appDoesNotOwnCLIInstallation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for path in [
            "Scholium/Views/BootstrapAgentPreparationView.swift",
            "Scholium/Views/WorkspaceSetupView.swift",
            "Scholium/Features/Settings/WorkspaceSettingsModel.swift",
            "Scholium/Services/WindowSession.swift",
            "Scholium/App/ScholiumApp.swift",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            #expect(!source.contains("CommandLineToolInstaller"))
            #expect(!source.contains("commandLineToolStatus"))
            #expect(!source.contains("installCommandLineTool"))
        }
    }

    @Test("Agent preparation overlaps registration but Ready remains gated")
    func backgroundRegistrationOrder() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSetupView.swift"
            ),
            encoding: .utf8
        )
        let saveStart = try #require(source.range(of: "    private func save() {"))
        let saveEnd = try #require(source.range(
            of: "    private func loadCurrentValuesIfNeeded",
            range: saveStart.upperBound..<source.endIndex
        ))
        let save = String(source[saveStart.lowerBound..<saveEnd.lowerBound])
        let agentTransition = try #require(save.range(of: "move(to: .agent)"))
        let registration = try #require(save.range(
            of: "try await context.configure(selection)"
        ))

        #expect(agentTransition.lowerBound < registration.lowerBound)
        #expect(save.contains("if let pendingAgentOutcome"))
        #expect(save.contains("move(to: .reviewTriptych, movingForward: false)"))
    }

    @Test("Create-new prepares exactly one Triptych structure and refuses collisions")
    func createNewStructure() async throws {
        let manager = FileManager.default
        let testRoot = URL(
            fileURLWithPath: manager.currentDirectoryPath,
            isDirectory: true
        )
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("bootstrap-structure-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: testRoot) }

        let preparer = BootstrapTriptychStructurePreparer()
        let prepared = try await preparer.prepare(
            parentURL: testRoot,
            name: "Emotion/Reasons"
        )

        #expect(prepared.rootURL.lastPathComponent == "Emotion-Reasons")
        for folder in [
            prepared.analysesURL,
            prepared.topicsURL,
            prepared.worksURL,
            prepared.rootURL.appendingPathComponent(".scholium", isDirectory: true),
        ] {
            var isDirectory: ObjCBool = false
            #expect(manager.fileExists(atPath: folder.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }

        do {
            _ = try await preparer.prepare(
                parentURL: testRoot,
                name: "Emotion/Reasons"
            )
            Issue.record("A second create-new attempt must not reuse an existing root")
        } catch BootstrapStructurePreparationError.destinationExists {
            // Expected: no overwrite or compatibility path.
        }
    }
}
