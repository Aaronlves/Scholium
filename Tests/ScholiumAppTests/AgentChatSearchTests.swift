import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Public conversation search")
struct AgentChatSearchTests {
    @Test("Literal Unicode queries search public plans, activities and exact material without changing history")
    func publicContent() {
        var conversation = AgentChatConversation(triptychID: UUID())
        conversation.title = "Reasons and 情绪"
        conversation.draft = "unsent private draft"
        let material = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "原文.md",
            text: "原文观点 👨‍👩‍👧‍👦 café", fingerprint: .init(content: "原文观点 👨‍👩‍👧‍👦 café"))
        var planMessage = AgentChatMessage(role: .assistant, text: "")
        planMessage.plan = .init(
            turnID: "turn", explanation: "比较解释",
            steps: [.init(step: "核对引文", status: .pending)])
        conversation.messages = [
            .init(role: .user, text: "Literal a+b?", attachments: [material]),
            planMessage,
            .init(
                role: .operation, text: "",
                activity: .init(
                    kind: .search, status: .completed,
                    source: .runtime, subject: "反例", detail: "检索结果")),
        ]
        let before = conversation
        for query in ["reasons", "情绪", "a+b?", "CAFE\u{301}", "原文观点", "核对引文", "检索结果"] {
            #expect(AgentChatSearch.contains(conversation, query: query))
        }
        #expect(!AgentChatSearch.contains(conversation, query: "unsent private draft"))
        #expect(!AgentChatSearch.contains(conversation, query: ".*"))
        #expect(AgentChatSearch.contains(conversation, query: ""))
        #expect(AgentChatSearch.query(" \n情绪\t") == "情绪")
        #expect(conversation == before)
    }

    @Test("List filters use observed activity and retain material-only and queued drafts")
    func listFilters() {
        var conversation = AgentChatConversation(triptychID: UUID())
        conversation.lastRunStatus = .running
        #expect(!AgentChatListFilter.hasDraft(conversation))
        #expect(AgentChatListFilter.all.includes(conversation, needsInput: false, inProgress: false))
        // Persisted prior status alone must not imply a current execution.
        #expect(!AgentChatListFilter.inProgress.includes(conversation, needsInput: false, inProgress: false))
        #expect(AgentChatListFilter.inProgress.includes(conversation, needsInput: false, inProgress: true))
        #expect(AgentChatListFilter.needsInput.includes(conversation, needsInput: true, inProgress: false))
        #expect(!AgentChatListFilter.needsInput.includes(conversation, needsInput: false, inProgress: true))
        conversation.queuedMessages = [.init(role: .user, text: "Queued question")]
        #expect(AgentChatListFilter.hasDraft(conversation))
        conversation.queuedMessages = []
        conversation.attachments = [
            .init(
                noteID: UUID(), vaultID: UUID(), relativePath: "Note.md",
                text: "Material", fingerprint: .init(content: "Material"))
        ]
        #expect(AgentChatListFilter.hasDraft(conversation))
        conversation.attachments = []
        conversation.childDrafts = ["child": "Unsent adjustment"]
        #expect(!AgentChatListFilter.hasDraft(conversation))
        conversation.childDrafts = [:]
        conversation.draft = "Unsent question"
        let before = conversation
        #expect(AgentChatListFilter.drafts.includes(conversation, needsInput: false, inProgress: false))
        #expect(conversation == before)
    }

    @Test("A passage retains the actual match and Unicode boundaries away from the start")
    func snippets() {
        let text = String(repeating: "😀文", count: 80) + "\nNeedle e\u{301}\n" + String(repeating: "后", count: 90)
        let passage = AgentChatSearch.snippet(text, query: "needle")
        #expect(passage.hasPrefix("…") && passage.hasSuffix("…"))
        #expect(passage.contains("Needle e\u{301}"))
        #expect(!passage.contains("\n") && !passage.contains("�"))
    }

    @Test("Predicates and snippets retain every public field without reading unsent or private state")
    func publicFieldCoverage() {
        let local = AgentChatLocalMaterial(
            id: UUID(), source: .file(URL(fileURLWithPath: "/Nonprivate/local-filename-token.pdf")),
            storedFileName: nil, fingerprint: nil, kind: .pdf, text: "local-body-token",
            pages: [.init(number: 1, text: "first-page-token"), .init(number: 9, text: "last-page-token")])
        let attachmentText = "attachment-body-token"
        var message = AgentChatMessage(
            id: "public-message", role: .assistant, text: "body-token CAFÉ e\u{301} 😀",
            attachments: [
                .init(
                    noteID: UUID(), vaultID: UUID(), relativePath: "attachment-path-token.md",
                    text: attachmentText, fingerprint: .init(content: attachmentText))
            ], localMaterials: [local])
        message.replyQuotes = [.init(conversationID: UUID(), messageID: "quoted", text: "quote-token")]
        message.coordinationTarget = .init(parentThreadID: "parent-token", childThreadID: "child-token", name: "name-token")
        message.methods = [.init(name: "method", title: "skill-title-token", path: "/Nonprivate/private-method-path")]
        message.plan = .init(turnID: "turn", explanation: "plan-explanation-token", steps: [.init(step: "plan-step-token", status: .pending)])
        message.activity = .init(
            kind: .delegation, status: .completed, source: .runtime,
            subject: "subject-token", detail: "detail-token", files: [.init(path: "file-path-token")])
        message.activity?.delegation = .init(
            operation: .wait, senderThreadID: "sender-token", prompt: "prompt-token",
            targets: [.init(id: "target-id-token", path: "target-path-token", state: .completed, message: "target-message-token")])
        var conversation = AgentChatConversation(triptychID: UUID())
        conversation.messages = [message]
        conversation.draft = "unsent-token"
        let unchanged = conversation
        let passages = [
            "body-token CAFÉ e\u{301} 😀", "quote-token", "name-token", "child-token", "parent-token", "skill-title-token",
            "plan-explanation-token", "plan-step-token", "subject-token", "detail-token", "file-path-token",
            "prompt-token", "sender-token", "target-id-token", "target-path-token", "target-message-token",
            "attachment-path-token.md", attachmentText, "local-filename-token.pdf", "local-body-token", "first-page-token", "last-page-token",
        ]
        for passage in passages {
            let query = passage.uppercased()
            #expect(AgentChatSearch.contains(message, query: query))
            #expect(AgentChatSearch.contains(conversation, query: query))
            #expect(AgentChatSearch.passage(in: message, query: query).map { Array($0.utf8) } == Array(passage.utf8))
        }
        for query in ["unsent-token", "private-method-path", ".*"] {
            #expect(!AgentChatSearch.contains(conversation, query: query))
            #expect(AgentChatSearch.passage(in: message, query: query) == nil)
        }
        #expect(AgentChatSearch.contains(conversation, query: ""))
        #expect(!AgentChatSearch.contains(message, query: ""))
        #expect(conversation == unchanged)
    }

    @Test("A current original Unicode range supplies the first matching passage after source replacement")
    func firstCurrentPassage() {
        let source = String(repeating: "界😀", count: 40) + "CAFE\u{301}" + String(repeating: "尾", count: 90)
        let expected = "…" + String(repeating: "界😀", count: 16) + "CAFE\u{301}" + String(repeating: "尾", count: 72) + "…"
        var message = AgentChatMessage(id: "current", role: .assistant, text: source)
        message.replyQuotes = [.init(conversationID: UUID(), messageID: "quoted", text: "A later CAFÉ quotation")]
        #expect(AgentChatSearch.passage(in: message, query: "café").map { Array($0.utf8) } == Array(expected.utf8))
        #expect(Array(message.text.utf8) == Array(source.utf8))
        message.text = "The replacement has no match."
        #expect(AgentChatSearch.passage(in: message, query: "café") == "A later CAFÉ quotation")
        message.replyQuotes = nil
        #expect(!AgentChatSearch.contains(message, query: "café"))
        #expect(AgentChatSearch.passage(in: message, query: "café") == nil)
    }

    @Test("Native UTF-16 search retains the prior Unicode range and exact displayed source")
    func nativeRangeDifferential() {
        let cases: [(name: String, text: String, query: String)] = [
            ("empty source", "", "needle"),
            ("empty query", "Public text", ""),
            ("both empty", "", ""),
            ("ASCII case", "before NeEdLe after needle", "NEEDLE"),
            ("literal punctuation", "literal .* and a+b?", ".*"),
            ("literal absent", "letters only", ".*"),
            ("NFC source", "pré CAFÉ fin", "cafe\u{301}"),
            ("NFD source", "pré CAFE\u{301} fin", "café"),
            ("accent remains significant", "café", "cafe"),
            ("combining scalar", "before e\u{301} after", "\u{301}"),
            ("CJK", "前文引用后文引用", "引用"),
            ("non-BMP", "前文😀后文😀", "😀"),
            ("ZWJ sequence", "before 👨‍👩‍👧‍👦 after", "👨‍👩‍👧‍👦"),
            ("ZWJ component", "before 👨‍👩‍👧‍👦 after", "👩"),
            ("ZWJ scalar", "before 👨‍👩‍👧‍👦 after", "\u{200D}"),
            ("variation sequence", "before ❤️ after", "❤️"),
            ("variation component", "before ❤️ after", "❤"),
            ("variation scalar", "before ❤️ after", "\u{FE0F}"),
            ("emoji modifier", "before 👍🏽 after", "🏽"),
            ("regional indicator", "before 🇨🇭 after", "🇨"),
            ("ZWJ partial then complete", "before 👨‍👩‍👧‍👦 later 👩 after", "👩"),
            ("combining partial then complete", "e\u{301}\n\u{301}\nafter", "\u{301}"),
            ("variation partial then complete", "❤️\n\u{FE0F}\nafter", "\u{FE0F}"),
            ("modifier partial then complete", "before 👍🏽\n🏽\nafter", "🏽"),
            ("regional partial then complete", "before 🇨🇭 later 🇨 after", "🇨"),
            ("Greek case fold", "before Σίσυφος σς after", "Σ"),
            ("expanding case fold", "before Straße after", "STRASSE"),
            ("Kelvin case fold", "before Kelvin after", "kelvin"),
            ("dotted I", "before İstanbul after", "istanbul"),
            ("dotless I", "before ı after", "I"),
            ("CRLF passage", "before\r\nNeedle\r\nafter", "NEEDLE"),
            ("CRLF query", "before\r\nNeedle\r\nafter", "\r\n"),
            ("LF query", "before\nNeedle\nafter", "\nNeedle"),
            ("lone CR", "before\rNeedle\rafter", "needle"),
            (
                "bounded mixed Unicode",
                String(repeating: "界👨‍👩‍👧‍👦e\u{301}", count: 40)
                    + "MATCH_POINT😀" + String(repeating: "❤️尾", count: 60), "match_point😀"
            ),
        ]
        for item in cases {
            // The fidelity oracle uses the prior String API independently
            // of the production matcher and compares offsets in the unchanged source.
            let priorRange = item.text.range(of: item.query, options: .caseInsensitive)
            let expectedRange = priorRange.map { NSRange($0, in: item.text) }
            let nativeRange = AgentChatSearch.matchedRange(in: item.text, query: item.query)
            #expect(nativeRange == expectedRange, "Range differs for \(item.name)")
            let expectedMatch = !item.query.isEmpty && priorRange != nil
            let expectedPassage = expectedMatch ? priorRange.map { priorSnippet(item.text, range: $0) } : nil
            let message = AgentChatMessage(id: item.name, role: .assistant, text: item.text)
            let originalBytes = Array(message.text.utf8)
            #expect(AgentChatSearch.matches(item.text, query: item.query) == expectedMatch, "Predicate differs for \(item.name)")
            #expect(AgentChatSearch.contains(message, query: item.query) == expectedMatch, "Message differs for \(item.name)")
            #expect(
                AgentChatSearch.passage(in: message, query: item.query).map { Array($0.utf8) }
                    == expectedPassage.map { Array($0.utf8) }, "Passage differs for \(item.name)")
            #expect(
                Array(AgentChatSearch.snippet(item.text, query: item.query).utf8)
                    == Array((expectedPassage ?? "").utf8), "Snippet differs for \(item.name)")
            #expect(Array(message.text.utf8) == originalBytes)
        }
    }

    @Test("Known snippets preserve whole contextual characters and exact CRLF projection")
    func nativeKnownSnippets() {
        let family = "👨‍👩‍👧‍👦"
        let suffixPair = "e\u{301}❤️"
        let source = String(repeating: family, count: 40) + "Needle" + String(repeating: suffixPair, count: 45)
        let expected = "…" + String(repeating: family, count: 32) + "Needle" + String(repeating: suffixPair, count: 36) + "…"
        #expect(Array(AgentChatSearch.snippet(source, query: "NEEDLE").utf8) == Array(expected.utf8))
        #expect(AgentChatSearch.snippet("before\r\nNeedle\r\nafter", query: "needle") == "before  Needle  after")
        #expect(AgentChatSearch.snippet("before\rNeedle\nafter", query: "needle") == "before Needle after")
        #expect(AgentChatSearch.snippet("before 👨‍👩‍👧‍👦 and ❤️ after", query: "👩") == "")
        #expect(AgentChatSearch.snippet("before 👨‍👩‍👧‍👦 and ❤️ after", query: "\u{FE0F}") == "")
    }

    @Test("Snippet conversion rejects missing, overflow, out-of-bounds and partial-surrogate ranges")
    func invalidNativeRanges() {
        let source = "😀 e\u{301} 👨‍👩‍👧‍👦 ❤️"
        let invalid = [
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: -1, length: 1),
            NSRange(location: 0, length: -1),
            NSRange(location: 0, length: 0),
            NSRange(location: source.utf16.count, length: 1),
            NSRange(location: source.utf16.count + 1, length: 1),
            NSRange(location: 1, length: Int.max),
            NSRange(location: Int.max - 1, length: 4),
            NSRange(location: 0, length: 1),
            NSRange(location: 1, length: 1),
            NSRange(location: 1, length: 2),
            NSRange(location: 4, length: 1),
        ]
        for range in invalid {
            #expect(AgentChatSearch.snippet(source, range: range) == nil)
        }
        #expect(AgentChatSearch.snippet(source, range: NSRange(location: 0, length: 2)) == source)
        #expect(AgentChatSearch.snippet("", range: NSRange(location: 0, length: 1)) == nil)
    }

    @Test("Native candidates require explicit Character boundaries after range conversion")
    func nativeCharacterBoundaries() {
        let cases: [(text: String, query: String, accepted: Bool)] = [
            ("CAFE\u{301}", "café", true), ("😀", "😀", true),
            ("👨‍👩‍👧‍👦", "👨‍👩‍👧‍👦", true), ("❤️", "❤️", true),
            ("e\u{301}", "\u{301}", false), ("👨‍👩‍👧‍👦", "👩", false),
            ("❤️", "\u{FE0F}", false), ("👍🏽", "🏽", false), ("🇨🇭", "🇨", false),
        ]
        for item in cases {
            let native = (item.text as NSString).range(of: item.query, options: .caseInsensitive)
            #expect(native.location != NSNotFound && native.length > 0)
            let lower = item.text.utf16.index(item.text.utf16.startIndex, offsetBy: native.location)
            let upper = item.text.utf16.index(lower, offsetBy: native.length)
            let bothBoundaries = lower.samePosition(in: item.text) != nil && upper.samePosition(in: item.text) != nil
            #expect(bothBoundaries == item.accepted)
            let convertedBoundaries =
                Range(native, in: item.text).map {
                    $0.lowerBound.samePosition(in: item.text) != nil && $0.upperBound.samePosition(in: item.text) != nil
                } ?? false
            #expect(convertedBoundaries == item.accepted)
        }
    }

    @Test("An earlier partial Character match does not hide a later complete match in the same public field")
    func laterCompleteCharacterMatch() throws {
        let cases = [
            ("e\u{301}\n\u{301}", "\u{301}"), ("👨‍👩‍👧‍👦\n👩", "👩"),
            ("❤️\n\u{FE0F}", "\u{FE0F}"), ("👍🏽\n🏽", "🏽"), ("🇨🇭\n🇨", "🇨"),
        ]
        for (source, query) in cases {
            let firstNative = (source as NSString).range(of: query, options: .caseInsensitive)
            let expected = try #require(source.range(of: query, options: .caseInsensitive))
            let expectedRange = NSRange(expected, in: source)
            #expect(firstNative.location < expectedRange.location)
            #expect(AgentChatSearch.matchedRange(in: source, query: query) == expectedRange)
            var message = AgentChatMessage(id: "later-complete", role: .assistant, text: source)
            message.replyQuotes = [.init(conversationID: UUID(), messageID: "quote", text: "A later quote \(query)")]
            #expect(AgentChatSearch.contains(message, query: query))
            #expect(
                AgentChatSearch.passage(in: message, query: query).map { Array($0.utf8) }
                    == Array(priorSnippet(source, range: expected).utf8))
        }
    }

    private func priorSnippet(_ text: String, range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -32, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 72, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…")
            + text[start..<end].components(separatedBy: .newlines).joined(separator: " ")
            + (end == text.endIndex ? "" : "…")
    }

    @Test("Find preserves the current message during streaming and wraps without stale destinations")
    func navigation() {
        var messages = [
            AgentChatMessage(id: "a", role: .user, text: "理由 理由"),
            .init(id: "b", role: .assistant, text: "另一种理由"),
        ]
        var find = AgentChatFindState()
        find.query = "理由"
        find.refresh(messages: messages)
        #expect(find.messageIDs == ["a", "b"] && find.position == 1)
        find.move(backwards: true)
        #expect(find.selectedID == "b" && find.position == 2)
        messages.append(.init(id: "c", role: .assistant, text: "理由的新解释"))
        find.refresh(messages: messages)
        #expect(find.selectedID == "b")
        find.move(backwards: false)
        #expect(find.selectedID == "c")
        find.move(backwards: false)
        #expect(find.selectedID == "a")
        find.query = "不存在"
        find.refresh(messages: messages, reset: true)
        find.move(backwards: false)
        #expect(find.selectedID == nil && find.position == nil && find.messageIDs.isEmpty)
        find.query = "理由"
        find.refresh(messages: messages)
        find.refresh(messages: Array(messages.dropFirst()))
        #expect(find.selectedID == "b")
    }

    @MainActor
    @Test("Optional search commands preserve marked text and ordinary search-field behavior")
    func nativeCommands() {
        var navigation: [Bool] = []
        var dismissals = 0
        let coordinator = ContextSearchField.Coordinator(
            parent: .init(
                text: .constant(""),
                prompt: "Find in Conversation", identifier: "fixture",
                navigate: { navigation.append($0) }, dismiss: { dismissals += 1 }))
        let field = ContextSearchField.Field()
        let editor = NSTextView()
        let enter = #selector(NSResponder.insertNewline(_:))
        let escape = #selector(NSResponder.cancelOperation(_:))
        #expect(coordinator.control(field, textView: editor, doCommandBy: enter))
        #expect(navigation == [false])
        editor.setMarkedText(
            "候选", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!coordinator.control(field, textView: editor, doCommandBy: enter))
        #expect(!coordinator.control(field, textView: editor, doCommandBy: escape))
        #expect(navigation.count == 1 && dismissals == 0)
        editor.unmarkText()
        #expect(coordinator.control(field, textView: editor, doCommandBy: escape))
        #expect(dismissals == 1)
        coordinator.parent.navigate = nil
        coordinator.parent.dismiss = nil
        #expect(!coordinator.control(field, textView: editor, doCommandBy: enter))
        #expect(!coordinator.control(field, textView: editor, doCommandBy: escape))
    }
}
