import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Native research conversation presentation")
struct AgentChatPresentationTests {
    @Test("Research progress never promotes raw commands or paths into its primary summary")
    func quietProgress() {
        let command = AgentChatActivity(
            kind: .command, status: .failed, source: .runtime,
            subject: "cat /private/path/file", detail: "EACCES raw error")
        #expect(AgentChatActivityProjection.title(command, locale: Locale(identifier: "zh-Hans")) == "运行命令")
        #expect(AgentChatActivityProjection.subject(command) == nil)
        let note = AgentChatActivity(
            kind: .read, status: .completed, source: .scholium,
            subject: "internal-id", detail: "raw", files: [.init(path: "Analyses/原文.md")])
        #expect(AgentChatActivityProjection.subject(note) == "原文.md")
        #expect(command.detail == "EACCES raw error")
    }

    @Test("Sources retain web, Note and other explicit locators without manufacturing citations")
    func replySources() {
        let note = AgentChatReference.url(noteID: UUID())
        let sources = AgentChatReplySource.collect(
            "[Note](\(note)) [Web](https://example.org/source) [Again](https://example.org/source) [PDF](../paper.pdf) [Unsafe](javascript:alert) ordinary uncited text"
        )
        #expect(sources.count == 4)
        #expect(sources[0].isNote && !sources[0].isWeb)
        #expect(sources[1].isWeb && sources[1].destination == "example.org")
        #expect(!sources[2].isWeb && !sources[2].isNote)
        #expect(!sources[3].isWeb && !sources[3].isNote)
    }

    @Test("Public commentary and each tool call group only within their confirmed turn; final and unknown phases stay visible")
    func processGrouping() {
        var progress = AgentChatMessage(role: .assistant, text: "Checking", phase: .commentary)
        progress.turnID = "one"
        var operation = AgentChatMessage(role: .operation, text: "Read")
        operation.turnID = "one"
        var final = AgentChatMessage(role: .assistant, text: "Answer", phase: .finalAnswer)
        final.turnID = "one"
        var other = AgentChatMessage(role: .operation, text: "Another turn")
        other.turnID = "two"
        let unknown = AgentChatMessage(role: .assistant, text: "Unclassified answer")
        let items = AgentChatTimelineItem.group([progress, operation, operation, final, other, unknown])
        #expect(items.count == 4 && items[0].isProcess && items[0].messages.count == 3)
        #expect(!items[1].isProcess && items[2].isProcess && !items[3].isProcess)
        #expect(items.flatMap(\.messages) == [progress, operation, operation, final, other, unknown])
    }

    @Test("Reply sources preserve exact Note references without treating external URLs or paths as files")
    func replyFileReferences() throws {
        let note = UUID()
        let url = AgentChatReference.url(noteID: note)
        let text = "[论证](\(url)) and [again](\(url)) [website](https://example.org/paper.pdf) ordinary.md"
        let files = AgentChatReplySource.collect(text).filter(\.isNote)
        #expect(files.count == 1 && files.first?.url == url && files.first?.title == "论证")
    }

    @Test("Long replies preserve paragraphs, quotation, argument numbering and exact code")
    func markdownBlocks() {
        let source =
            "## A distinction\n\nA **strong** claim.\n\nA second paragraph with 中文 😀.\n\n> Source quotation.\n\n3. Premise\n4. Conclusion\n\n```text\na < b\n  exact spacing\n```"
        let blocks = AgentChatMarkdownBlock.parse(source)
        #expect(
            blocks.map(\.kind) == [.heading, .prose, .prose, .quote, .list("3."), .list("4."), .code])
        #expect(String(blocks[2].text.characters) == "A second paragraph with 中文 😀.")
        #expect(String(blocks[6].text.characters) == "a < b\n  exact spacing\n")
        #expect(
            blocks[1].text.runs.contains {
                $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            })
        #expect(Set(blocks.map(\.id)).count == blocks.count)
        #expect(AgentChatMarkdownBlock.parse("> 1. Quoted premise").first?.isQuoted == true)
    }

    @Test("Note citations remain links and comparison tables retain cells")
    func referencesAndTables() throws {
        let url = AgentChatReference.url(
            noteID: UUID(), line: 5,
            revision: DocumentFingerprint(content: "Exact source\r\n"), vaultID: UUID())
        let blocks = AgentChatMarkdownBlock.parse(
            "Read [this note](\(url)).\n\n| View | Objection |\n|---|---|\n| One | Two |")
        #expect(blocks.first?.text.runs.contains { $0.link == url } == true)
        #expect(blocks[1].kind == .tableRow(true))
        #expect(blocks[1].cells.map { String($0.characters) } == ["View", "Objection"])
        #expect(blocks[2].cells.map { String($0.characters) } == ["One", "Two"])
    }

    @Test("Activity can collapse without hiding replies or losing exact change links")
    func timeline() {
        let change = UUID()
        let messages: [AgentChatMessage] = [
            .init(role: .user, text: "Explain."),
            .init(role: .operation, text: "Read"),
            .init(role: .operation, text: "Updated", changeID: change),
            .init(role: .assistant, text: "First paragraph."),
            .init(role: .assistant, text: "Second paragraph."),
            .init(role: .user, text: "An objection."),
        ]
        let items = AgentChatTimelineItem.group(messages)
        #expect(items.count == 5)
        #expect(items[1].isProcess && items[1].messages.count == 2)
        #expect(items[1].messages[1].changeID == change)
        #expect(items.flatMap(\.messages) == messages)
    }

    @Test("Runtime status and reported edits never manufacture Scholium mutation evidence")
    func runtimeEvidence() throws {
        let own: [String: MCPJSONValue] = [
            "type": .string("mcpToolCall"),
            "server": .string("scholium"), "tool": .string("scholium_update_note"),
        ]
        #expect(AgentChatActivityProjection.withLocalizedFailure(CodexChatActivity.parse(own, completed: false)) == nil)
        let item: [String: MCPJSONValue] = [
            "type": .string("fileChange"), "status": .string("completed"),
            "changes": .array([
                .object([
                    "path": .string("fixture.md"), "diff": .string("-old\n+new"),
                    "kind": .object(["type": .string("update")]),
                ])
            ]),
        ]
        let activity = try #require(AgentChatActivityProjection.withLocalizedFailure(CodexChatActivity.parse(item, completed: true)))
        let message = AgentChatMessage(role: .operation, text: "", activity: activity)
        #expect(message.activity?.source == .runtime && message.changeID == nil)
        #expect(message.activity?.files.first?.effect == .edited)
        var pending = activity
        pending.status = .running
        #expect(AgentChatActivityProjection.afterConnectionLoss(pending).status == .uncertain)
        pending.status = .waitingForApproval
        #expect(AgentChatActivityProjection.afterConnectionLoss(pending).status == .interrupted)
        var failed = item
        failed["status"] = .string("failed")
        let failure = try #require(AgentChatActivityProjection.withLocalizedFailure(CodexChatActivity.parse(failed, completed: true)))
        #expect(failure.status == .failed && failure.files.first?.effect == nil)
    }

    @Test("Conversation change history retains earlier receipts without importing unrelated changes")
    func conversationChangeScope() {
        let triptych = UUID()
        let note = UUID()
        func change(_ time: Double) -> AgentChange {
            AgentChange(
                id: UUID(), triptychID: triptych, operation: .update, noteID: note,
                role: .topicKnowledge, originalRelativePath: "note.md", finalRelativePath: "note.md",
                beforeFingerprint: nil, afterFingerprint: nil, state: .confirmed,
                createdAt: Date(timeIntervalSince1970: time), confirmedAt: Date(timeIntervalSince1970: time), undoneAt: nil)
        }
        let earlier = change(1)
        let latest = change(2)
        let unrelated = change(3)
        let all = [earlier, latest, unrelated]
        #expect(
            AgentChangePresentation.inScope(all, scope: .conversation([earlier.id, latest.id, latest.id])).map(\.id)
                == [earlier.id, latest.id])
        #expect(AgentChangePresentation.inScope(all, scope: .exact(earlier.id)).map(\.id) == [earlier.id])
        #expect(AgentChangePresentation.inScope(all, scope: .current).map(\.id) == [unrelated.id])
        #expect(AgentChangePresentation.inScope(all, scope: .conversation([])).isEmpty)
    }

}
