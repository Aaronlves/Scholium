import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent chat activity Orb presentation")
struct AgentChatActivityOrbTests {
    @Test("Orb styles follow confirmed public activity kinds")
    func publicActivityMapping() {
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .search, source: .scholium)) == .searching)
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .webSearch, source: .runtime)) == .searching)
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .tool, source: .runtime)) == .connecting)
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .delegation, source: .runtime)) == .weaving)
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .read, source: .scholium)) == .working)
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .create, source: .scholium)) == .composing)
        #expect(
            AgentChatActivityOrbStyle.style(for: .init(kind: .compaction, source: .runtime)) == .breathing)

        var searchCommand = AgentChatActivity(kind: .command, source: .runtime)
        searchCommand.commandAction = .init(kind: .search, target: "argument")
        #expect(AgentChatActivityOrbStyle.style(for: searchCommand) == .searching)

        var readCommand = AgentChatActivity(kind: .command, source: .runtime)
        readCommand.commandAction = .init(kind: .read, target: "Topics/argument.md")
        #expect(AgentChatActivityOrbStyle.style(for: readCommand) == .working)
    }

    @Test("Waiting and terminal activity never receives an animated Orb")
    func lifecycleMapping() {
        for status in [
            AgentChatActivity.Status.waitingForApproval,
            .waitingForInput,
            .completed,
            .failed,
            .declined,
            .interrupted,
            .uncertain,
        ] {
            let activity = AgentChatActivity(kind: .tool, status: status, source: .runtime)
            #expect(AgentChatActivityOrbStyle.style(for: activity) == nil)
        }
    }

}
