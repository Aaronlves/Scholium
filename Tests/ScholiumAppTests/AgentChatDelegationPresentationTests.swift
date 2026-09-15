import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Delegation report summaries") @MainActor
struct AgentChatDelegationPresentationTests {
    private let locale = Locale(identifier: "en")

    @Test("A completed coordination call never announces that its Agents completed")
    func completedCoordination() {
        for operation in [AgentChatDelegation.Operation.spawnAgent, .wait, .sendInput, .listAgents] {
            let report = AgentChatDelegation(
                operation: operation, senderThreadID: "parent", prompt: nil,
                targets: [.init(id: "child", path: "/root/source-check", state: .running)])
            let presentation = AgentChatDelegationPresentation(report: report, operationStatus: .completed, locale: locale)
            #expect(presentation.summary.contains("/root/source-check"))
            #expect(!presentation.summary.contains("Completed"))
            #expect(presentation.visibleStatus == nil)
            #expect(presentation.report.targets.first?.state == .running)
        }
    }

    @Test("Opaque IDs use a count in the summary while retaining exact opening targets")
    func opaqueIdentity() {
        let id = "a113f3e0-63dc-44b0-a7d8-a4e63cfb2fea"
        for path in [nil, "", "  ", id] as [String?] {
            let report = AgentChatDelegation(
                operation: .spawnAgent, senderThreadID: "parent", prompt: "Exact request\n",
                targets: [.init(id: id, path: path, state: .pendingInit)])
            let presentation = AgentChatDelegationPresentation(report: report, operationStatus: .completed, locale: locale)
            #expect(!presentation.summary.contains(id))
            #expect(presentation.summary.contains("1"))
            #expect(presentation.report.targets.first?.id == id)
            #expect(presentation.report.prompt == "Exact request\n")
        }
    }

    @Test("Unknown and failed reported states stay visible after successful coordination")
    func retainedIssues() throws {
        let report = AgentChatDelegation(
            operation: .wait, senderThreadID: "parent", prompt: nil,
            targets: [
                .init(id: "running", state: .running),
                .init(id: "failed", state: .errored, message: "Exact failure\n"),
                .init(id: "missing", state: nil),
                .init(id: "not-found", state: .notFound),
            ])
        let presentation = AgentChatDelegationPresentation(report: report, operationStatus: .completed, locale: locale)
        let status = try #require(presentation.visibleStatus)
        #expect(status.contains(AgentChatDelegation.State.errored.label(locale: locale)))
        #expect(status.contains(ScholiumL10n.string("State Unavailable", locale: locale)))
        #expect(status.contains(AgentChatDelegation.State.notFound.label(locale: locale)))
        #expect(!status.contains("Completed"))
        #expect(presentation.report.targets[1].message == "Exact failure\n")
    }

    @Test("Call interruption and uncertainty remain distinct from a previously completed target")
    func operationOutcomes() {
        let report = AgentChatDelegation(
            operation: .sendMessage, senderThreadID: "parent", prompt: nil,
            targets: [.init(id: "child", state: .completed)])
        for status in [AgentChatActivity.Status.running, .failed, .uncertain, .interrupted, .waitingForApproval, .waitingForInput] {
            let presentation = AgentChatDelegationPresentation(report: report, operationStatus: status, locale: locale)
            #expect(presentation.visibleStatus == status.label(locale: locale))
        }
    }
}
