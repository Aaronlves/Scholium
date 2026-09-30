import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Markdown file launch routing")
struct MarkdownFileOpeningLaunchTests {
    @Test("Published file admission is consumed after its willSet emission")
    func deferredBootstrapAdmission() async throws {
        let opening = MarkdownFileOpeningController()
        var consumption: Task<Bool, Never>?
        let observation = opening.$handlesLaunchDocuments.sink { handlesDocuments in
            guard handlesDocuments else { return }
            consumption = Task { @MainActor in opening.consumeLaunchBootstrapSuppression() }
        }
        defer { observation.cancel() }
        opening.requestOpen([file("Initial.md")])
        let task = try #require(consumption)
        #expect(await task.value)
        #expect(!opening.handlesLaunchDocuments)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Managed routing respects the Note inventory and leaves attachment originals external")
    func inventoryRoutingEligibility() {
        let root = URL(fileURLWithPath: "/nonexistent-scholium-routing-fixture/Topics")
        for excluded in ["Attachments/Original.md", ".scholium/state.md", "Nested/.hidden/Original.md", "Outside.markdown", "../Outside.md"] {
            #expect(MarkdownFileOpeningController.managedMarkdownRelativePath(at: root.appendingPathComponent(excluded), in: root) == nil)
        }
        #expect(MarkdownFileOpeningController.managedMarkdownRelativePath(at: root.appendingPathComponent("Nested/Note.md"), in: root) == "Nested/Note.md")
        #expect(
            MarkdownFileOpeningController.managedMarkdownRelativePath(at: root.appendingPathComponent("Nested/Attachments/Note.md"), in: root)
                == "Nested/Attachments/Note.md")
    }

    @Test("A queued launch file suppresses only the initial Bootstrap, even when it attaches after launch finishes")
    func pendingLaunchSurvivesUntilBootstrapConsumesIt() {
        let opening = MarkdownFileOpeningController()
        opening.requestOpen([file("Initial.md")])
        opening.finishLaunching()

        #expect(opening.handlesLaunchDocuments)
        #expect(opening.consumeLaunchBootstrapSuppression())
        #expect(!opening.handlesLaunchDocuments)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Several initial file events cannot rearm suppression after the launch Bootstrap consumes it")
    func multipleLaunchFilesConsumeOnlyOneBootstrap() {
        let opening = MarkdownFileOpeningController()
        opening.requestOpen([file("First.md")])
        #expect(opening.consumeLaunchBootstrapSuppression())

        opening.requestOpen([file("Second.markdown"), file("Third.md")])

        #expect(!opening.handlesLaunchDocuments)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Opening a file in a running app cannot suppress a later ordinary Bootstrap or Dock reopen")
    func warmOpeningDoesNotSuppressBootstrap() {
        let opening = MarkdownFileOpeningController()
        opening.finishLaunching()
        opening.requestOpen([file("Later.md")])

        #expect(!opening.handlesLaunchDocuments)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Empty events and rejected termination-time events never acquire launch suppression")
    func nonadmittedRequestsDoNotSuppressBootstrap() {
        let opening = MarkdownFileOpeningController()
        opening.requestOpen([])
        #expect(!opening.consumeLaunchBootstrapSuppression())
        opening.prepareTermination()
        opening.requestOpen([file("Rejected.md")])
        #expect(!opening.consumeLaunchBootstrapSuppression())
        opening.cancelTermination()
        opening.requestOpen([file("Admitted.md")])
        #expect(opening.consumeLaunchBootstrapSuppression())
    }

    private func file(_ name: String) -> URL {
        // Routing is deliberately unbound: these URL events exercise launch
        // admission without opening a window, file session or real vault.
        URL(fileURLWithPath: "/nonexistent-scholium-launch-fixture/\(name)")
    }
}
