import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("One-shot workspace bootstrap")
struct WorkspaceBootstrapTests {
    @Test("Candidate rendering is bounded and candidate-only")
    func rendersCandidateWithoutWriting() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try WorkspaceBootstrap.candidate(
            for: WorkspaceBootstrapRequest(
                triptychSelector: "triptych-123",
                triptychName: "Ethics Research",
                targetURL: fixture.target,
                researcherConventions: "Use the researcher\'s exact terminology."
            )
        )

        #expect(candidate.triptychSelector == "triptych-123")
        #expect(candidate.triptychName == "Ethics Research")
        #expect(candidate.content.contains("Triptych selector: `triptych-123`"))
        #expect(candidate.content.contains("Use the researcher\'s exact terminology."))
        #expect(candidate.content.contains("scholium workspace skill-sources"))
        #expect(candidate.content.contains("scholium agent start"))
        #expect(candidate.content.contains(
            "An instruction file or Skill discovery link never grants note-edit permission."
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.target.appendingPathComponent("AGENTS.md").path
        ))
    }

    @Test("An existing ancestor AGENTS.md stops bootstrap")
    func existingInstructionsStopBootstrap() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ancestorInstructions = fixture.root.appendingPathComponent("AGENTS.md")
        try "# Existing instructions\n".write(to: ancestorInstructions, atomically: true, encoding: .utf8)

        do {
            _ = try WorkspaceBootstrap.candidate(
                for: WorkspaceBootstrapRequest(
                    triptychSelector: "triptych-123",
                    triptychName: "Ethics Research",
                    targetURL: fixture.target
                )
            )
            Issue.record("An applicable AGENTS.md must stop bootstrap.")
        } catch let error as WorkspaceBootstrapError {
            guard case .applicableInstructions(let paths) = error else {
                Issue.record("Unexpected bootstrap error: \(error.localizedDescription)")
                return
            }
            #expect(paths == [ancestorInstructions.path])
        }
    }

    @Test("An external agent can promote, read back, and clean up one candidate")
    func externalAgentPromotionSimulation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try WorkspaceBootstrap.candidate(
            for: WorkspaceBootstrapRequest(
                triptychSelector: "triptych-123",
                triptychName: "Ethics Research",
                targetURL: fixture.target
            )
        )
        let temporaryCandidate = fixture.root.appendingPathComponent(
            "task-owned-workspace-bootstrap.md"
        )
        let destination = fixture.target.appendingPathComponent("AGENTS.md")

        try Data(candidate.content.utf8).write(to: temporaryCandidate, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: temporaryCandidate.path))

        _ = try WorkspaceBootstrap.validateTarget(fixture.target)
        try FileManager.default.copyItem(at: temporaryCandidate, to: destination)
        let readBack = try String(contentsOf: destination, encoding: .utf8)
        #expect(readBack == candidate.content)

        try FileManager.default.removeItem(at: temporaryCandidate)
        #expect(!FileManager.default.fileExists(atPath: temporaryCandidate.path))
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("The Scholium checkout is never a researcher workspace target")
    func applicationCheckoutStopsBootstrap() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try "// package marker\n".write(
            to: fixture.root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent("ScholiumCore"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent("Scholium"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent("Docs"),
            withIntermediateDirectories: true
        )
        try "# Scholium Specification\n".write(
            to: fixture.root.appendingPathComponent("Docs/SCHOLIUM_SPEC.md"),
            atomically: true,
            encoding: .utf8
        )

        do {
            _ = try WorkspaceBootstrap.validateTarget(fixture.target)
            Issue.record("The application checkout must be rejected.")
        } catch let error as WorkspaceBootstrapError {
            guard case .applicationCheckout(let path) = error else {
                Issue.record("Unexpected bootstrap error: \(error.localizedDescription)")
                return
            }
            #expect(path == fixture.root.path)
        }
    }

    private struct Fixture {
        let root: URL
        let target: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("scholium-bootstrap-\(UUID().uuidString)", isDirectory: true)
            target = root.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
