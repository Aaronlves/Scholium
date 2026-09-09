import Foundation
import Testing
@testable import ScholiumContracts

struct AgentChatCommandOutputTests {
    private func command(_ text: String) -> AgentChatActivity {
        .init(kind: .command, source: .runtime, detail: text)
    }
    @Test func aggregatesAndTailOnlyCompletionPreserveStream() {
        let old = command("first\nsecond\n")
        #expect(AgentChatCommandOutput.reconciling(command("first\nsecond\nlast\n"), with: old).detail == "first\nsecond\nlast\n")
        #expect(AgentChatCommandOutput.reconciling(command("second\nlast\n"), with: old).detail == "first\nsecond\nlast\n")
        #expect(AgentChatCommandOutput.reconciling(command("second\n"), with: old).detail == old.detail)
        #expect(AgentChatCommandOutput.reconciling(command(""), with: old).detail == old.detail)
    }
    @Test func boundedUnicodeOutputAndDisclosureSurvivePersistence() throws {
        var activity = command("")
        AgentChatCommandOutput.appending(String(repeating: "论证😀", count: 40_000), to: &activity)
        #expect(activity.detail.utf8.count <= AgentChatCommandOutput.maximumUTF8Bytes)
        #expect(!activity.detail.contains("�"))
        #expect(activity.outputTruncated == true)
        let decoded = try JSONDecoder().decode(AgentChatActivity.self, from: JSONEncoder().encode(activity))
        #expect(decoded == activity)
        #expect(AgentChatCommandOutput.reconciling(command("last"), with: decoded).outputTruncated == true)
    }
    @Test func shorterLogsRemainCompleteAndOtherActivitiesKeepTheirOwnMeaning() {
        var activity = command("")
        let text = String(repeating: "x", count: 30_000)
        AgentChatCommandOutput.appending(text, to: &activity)
        #expect(activity.detail == text && activity.outputTruncated != true)
        let tool = AgentChatActivity(kind: .tool, source: .runtime, detail: "result")
        #expect(AgentChatCommandOutput.reconciling(tool, with: activity) == tool)
    }
}
