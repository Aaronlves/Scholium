import Foundation
import Testing

@testable import ScholiumApp

@Suite("Selection writing results", .serialized)
@MainActor
struct AgentSelectionResultTests {
    @Test("Regeneration retains variants and hands off the inspected version without adopting")
    func versionsAndHandoff() async {
        var replies = ["First **proposal**\r\n", "Second proposal"]
        var handoff: String?
        var adopted = false
        let result = AgentSelectionResult(
            title: "Polish", original: "Original", adopt: { _ in adopted = true }, openReference: { _ in false },
            generate: { replies.removeFirst() }, continueInChat: { handoff = $0 })
        result.regenerate()
        await finish(result)
        #expect(result.finalReply == "First **proposal**\r\n")
        result.regenerate()
        #expect(result.finalReply == "First **proposal**\r\n")
        await finish(result)
        #expect(result.versions.count == 2 && result.finalReply == "Second proposal")
        result.previousVersion()
        result.continueInChat()
        #expect(handoff == "First **proposal**\r\n" && !adopted)
        result.adoptSelectedVersion()
        await finishAdoption(result)
        #expect(adopted && result.isAdopted)
        #expect(!result.canRegenerate)
        result.regenerate()
        #expect(!result.isGenerating && result.versions.count == 2)
    }

    @Test("Failed regeneration preserves the successful version with an inspectable error")
    func failureRetainsProposal() async {
        enum Failure: LocalizedError {
            case failed
            var errorDescription: String? { "Fixture failure" }
        }
        var attempts = 0
        let result = AgentSelectionResult(
            title: "Polish", original: "Original", adopt: nil, openReference: { _ in false },
            generate: {
                attempts += 1
                if attempts > 1 { throw Failure.failed }
                return "Retained proposal"
            }, continueInChat: { _ in })
        result.regenerate()
        await finish(result)
        result.regenerate()
        await finish(result)
        #expect(result.finalReply == "Retained proposal" && result.versions.count == 1)
        #expect(result.error == "Fixture failure" && result.canRegenerate)
    }

    @Test("Foreign diagnostic text remains exact across generation and adoption")
    func foreignDiagnosticBypassesCatalog() async {
        let raw = "Review"
        let failure = NSError(domain: "ForeignRuntimeFixture", code: 7, userInfo: [NSLocalizedDescriptionKey: raw])
        var attempts = 0
        let result = AgentSelectionResult(
            title: "Polish", original: "Original", adopt: { _ in throw failure },
            openReference: { _ in false },
            generate: {
                attempts += 1
                if attempts > 1 { throw failure }
                return "Exact proposal\r\n"
            }, continueInChat: { _ in })
        result.regenerate()
        await finish(result)
        result.regenerate()
        await finish(result)
        #expect(result.error == raw)
        #expect(result.finalReply == "Exact proposal\r\n")
        result.adoptSelectedVersion()
        await finishAdoption(result)
        #expect(result.adoptionError == raw)
        #expect(!result.isAdopted && result.canAdopt)
    }

    @Test("A cancelled generation cannot publish a late success or erase a prior result")
    func cancellationRejectsLateReply() async {
        let gate = GenerationGate()
        let result = AgentSelectionResult(
            title: "Explain", original: "Original", adopt: nil, openReference: { _ in false },
            generate: { await gate.reply() }, continueInChat: { _ in })
        result.regenerate()
        await gate.waitForStart()
        result.stop()
        gate.complete("Late reply")
        await finish(result)
        #expect(result.versions.isEmpty && result.finalReply == nil)
        #expect(result.isStopped && result.error == nil && result.canRegenerate)
    }

    @Test("A retained pending replacement admits once and keeps its selected version and failure")
    func retainedAdoptionLifecycle() async {
        let gate = AdoptionGate()
        var replies = ["First proposal", "Second proposal"]
        var handoffs = 0
        let result = AgentSelectionResult(
            title: "Polish", original: "Original", adopt: { try await gate.replace($0) },
            openReference: { _ in false }, generate: { replies.removeFirst() },
            continueInChat: { _ in handoffs += 1 })
        result.regenerate()
        await finish(result)
        result.regenerate()
        await finish(result)
        result.adoptSelectedVersion()
        await gate.waitForStart()

        // A reopened popover receives this same retained owner, not fresh view state.
        let reopened = result
        reopened.adoptSelectedVersion()
        reopened.previousVersion()
        reopened.nextVersion()
        reopened.regenerate()
        reopened.continueInChat()
        #expect(gate.proposals == ["Second proposal"])
        #expect(reopened.isAdopting && !reopened.canAdopt && !reopened.canContinueInChat)
        #expect(reopened.selectedVersionIndex == 1 && reopened.finalReply == "Second proposal")
        #expect(!reopened.isGenerating && handoffs == 0)

        gate.fail()
        await finishAdoption(reopened)
        #expect(reopened.adoptionError == "Synthetic replacement failed")
        #expect(!reopened.isAdopted && reopened.canAdopt)
        #expect(reopened.finalReply == "Second proposal")

        reopened.adoptSelectedVersion()
        await gate.waitForStart()
        #expect(reopened.adoptionError == nil)
        gate.complete()
        await finishAdoption(reopened)
        #expect(reopened.isAdopted && !reopened.canAdopt && !reopened.canRegenerate)
        reopened.adoptSelectedVersion()
        #expect(gate.proposals == ["Second proposal", "Second proposal"])
    }

    @Test("Chat handoff waits for generation to provide its completed selected version")
    func handoffWaitsForGeneration() async {
        let gate = GenerationGate()
        var handoffs: [String?] = []
        let result = AgentSelectionResult(
            title: "Explain", original: "Original", adopt: nil, openReference: { _ in false },
            generate: { await gate.reply() }, continueInChat: { handoffs.append($0) })
        result.regenerate()
        await gate.waitForStart()
        result.continueInChat()
        #expect(handoffs.isEmpty && !result.canContinueInChat)
        gate.complete("Completed explanation")
        await finish(result)
        result.continueInChat()
        #expect(handoffs == ["Completed explanation"])
    }

    @Test("Result Copy sends the exact inspected version and reports failed writes")
    func copySelectedVersion() async {
        let writer = RecordingPasteboardWriter()
        var replies = ["First **proposal**\r\n", "Second proposal"]
        let result = AgentSelectionResult(
            title: "Polish", original: "Original", adopt: nil, openReference: { _ in false },
            generate: { replies.removeFirst() }, continueInChat: { _ in })
        let view = AgentSelectionResultView(result: result, close: {}, pasteboardWriter: writer)

        #expect(!view.copyReply())
        #expect(writer.writes.isEmpty)

        result.regenerate()
        await finish(result)
        result.regenerate()
        await finish(result)
        #expect(result.finalReply == "Second proposal")
        result.previousVersion()
        #expect(result.finalReply == "First **proposal**\r\n")
        writer.succeeds = false
        #expect(!view.copyReply())
        #expect(writer.writes == ["First **proposal**\r\n"])

        writer.succeeds = true
        #expect(view.copyReply())
        #expect(writer.writes == ["First **proposal**\r\n", "First **proposal**\r\n"])
    }

    private func finish(_ result: AgentSelectionResult) async {
        for await generating in result.$isGenerating.values where !generating { return }
    }

    private func finishAdoption(_ result: AgentSelectionResult) async {
        for await adopting in result.$isAdopting.values where !adopting { return }
    }
}

@MainActor private final class RecordingPasteboardWriter: PasteboardWriting {
    var succeeds = true
    private(set) var writes: [String] = []

    func writeText(_ text: String) -> Bool {
        writes.append(text)
        return succeeds
    }
}

@MainActor private final class AdoptionGate {
    private enum Failure: LocalizedError {
        case failed
        var errorDescription: String? { "Synthetic replacement failed" }
    }
    private var pending: CheckedContinuation<Void, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var proposals: [String] = []

    func replace(_ text: String) async throws {
        proposals.append(text)
        try await withCheckedThrowingContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        guard pending == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func fail() {
        pending?.resume(throwing: Failure.failed)
        pending = nil
    }

    func complete() {
        pending?.resume()
        pending = nil
    }
}

@MainActor private final class GenerationGate {
    private var pending: CheckedContinuation<String, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func reply() async -> String {
        await withCheckedContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }
    func waitForStart() async {
        guard pending == nil else { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete(_ text: String) {
        pending?.resume(returning: text)
        pending = nil
    }
}
