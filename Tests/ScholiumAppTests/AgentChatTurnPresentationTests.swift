import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research turn status and elapsed time")
struct AgentChatTurnPresentationTests {
    @Test("Only the latest running activity in the live turn can pulse")
    func activeActivity() {
        func message(_ id: String, _ status: AgentChatActivity.Status, turn: String = "current") -> AgentChatMessage {
            var result = AgentChatMessage(
                id: id, role: .operation, text: "",
                activity: .init(kind: .read, status: status, source: .runtime))
            result.turnID = turn
            return result
        }
        let values = [
            message("running", .running), message("done", .completed),
            message("waiting", .waitingForInput), message("other", .running, turn: "other"),
        ]
        #expect(AgentChatTimelineItem.activeActivityID(in: values, turnID: "current") == "running")
        #expect(AgentChatTimelineItem.activeActivityID(in: values + [message("latest", .running)], turnID: "current") == "latest")
        #expect(AgentChatTimelineItem.activeActivityID(in: values, turnID: nil) == nil)
        #expect(AgentChatTimelineItem.activeActivityID(in: [message("done", .completed)], turnID: "current") == nil)
    }

    @Test("One status belongs to each exact turn, including an empty stopped turn and added user input")
    func statusPlacement() {
        func message(_ id: String, _ role: AgentChatMessage.Role, turn: String?) -> AgentChatMessage {
            var result = AgentChatMessage(id: id, role: role, text: id)
            result.turnID = turn
            return result
        }
        let request = message("request", .user, turn: "first")
        let addition = message("addition", .user, turn: "first")
        let reply = message("reply", .assistant, turn: "first")
        let next = message("next", .user, turn: "second")
        let unknown = message("unknown", .assistant, turn: nil)
        for (history, owners) in [
            ([request], ["request"]), ([request, addition], ["addition"]),
            ([request, reply, addition, next, unknown], ["reply", "next"]),
        ] {
            #expect(AgentChatTimelineItem.group(history).filter { $0.carriesTurnStatus(in: history) }.map(\.id) == owners)
        }
    }

    @Test("Only observed active work ticks; waiting and uncertain states never simulate thought")
    func activityTiming() {
        let start = Date(timeIntervalSince1970: 1_000)
        let timing = AgentChatTurnTiming(startedAt: start, completedAt: start.addingTimeInterval(38), durationMilliseconds: 38_500)
        let running = AgentChatTurnPresentation(state: .reading, timing: timing)
        #expect(running.seconds(at: start.addingTimeInterval(12)) == 12)
        #expect(running.elapsedLabel(at: start.addingTimeInterval(12), locale: Locale(identifier: "en")) == "Working for 12 s")
        #expect(running.seconds(at: start.addingTimeInterval(-1)) == nil)
        #expect(AgentChatTurnPresentation(state: .working).seconds(at: start) == nil)
        for state in [AgentChatTurnPresentation.State.waitingForInput, .waitingForApproval, .uncertain, .stopping] {
            let presentation = AgentChatTurnPresentation(state: state, timing: timing)
            #expect(!presentation.isWorking)
            #expect(presentation.seconds(at: start.addingTimeInterval(500)) == nil)
        }
        for state in [AgentChatTurnPresentation.State.completed, .failed, .interrupted] {
            let presentation = AgentChatTurnPresentation(state: state, timing: timing)
            #expect(!presentation.isWorking && presentation.seconds(at: start.addingTimeInterval(500)) == 38)
            #expect(presentation.elapsedLabel(at: start.addingTimeInterval(500), locale: Locale(identifier: "en")) == "Worked for 38 s")
        }
    }

    @Test("A late start cannot revive completed work or reset its retained duration")
    func lateAcknowledgement() throws {
        let finished = AgentChatTurnRecord(status: .completed, timing: .init(durationMilliseconds: 38_500))
        #expect(finished.merging(.init(status: .inProgress)) == finished)
        let decoded = try JSONDecoder().decode(AgentChatTurnRecord.self, from: JSONEncoder().encode(finished))
        #expect(decoded == finished && decoded.timing.completedSeconds == 38)
    }
}
