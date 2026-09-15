import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat input transforms into requests", .serialized)
@MainActor
struct AgentChatInputDockTests {
    private struct ComposerEnabledProbe: NSViewRepresentable {
        @Environment(\.isEnabled) private var isEnabled
        let record: (Bool) -> Void
        func makeNSView(context: Context) -> NSView { NSView() }
        func updateNSView(_ view: NSView, context: Context) { record(isEnabled) }
    }

    @Test("Resolving a request restores typing focus only when history reading has not taken over", arguments: [false, true])
    func requestResolutionPreservesReadingFocus(readingHistory: Bool) async throws {
        _ = NSApplication.shared
        var focused = false
        var composerEnabled: Bool?
        func content(requestID: String?, readingHistory: Bool) -> some View {
            AgentChatInputDock(
                requestID: requestID, requestTitle: "Answer Agent", requestCount: requestID == nil ? 0 : 1,
                isActive: true, isReadingHistory: readingHistory, isEditingDraft: false,
                composerIsFocused: Binding(get: { focused }, set: { focused = $0 })
            ) {
                Text("A pending question")
            } composer: {
                ComposerEnabledProbe(record: { composerEnabled = $0 }).frame(height: 60)
            }
        }
        let host = NSHostingView(rootView: content(requestID: "question", readingHistory: false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func awaitComposer(enabled: Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            repeat {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                await Task.yield()
            } while composerEnabled != enabled && ContinuousClock.now < deadline
            try #require(composerEnabled == enabled)
        }

        try await awaitComposer(enabled: false)
        #expect(!focused)
        // The researcher can start reading after a request has already opened.
        host.rootView = content(requestID: nil, readingHistory: readingHistory)
        try await awaitComposer(enabled: true)
        #expect(focused == !readingHistory)
    }

    @Test("Request presentation defers while the researcher is occupied and restores the draft after resolution")
    func presentationLifecycle() {
        var state = AgentChatInputDockState()
        let first = UUID().uuidString
        let second = UUID().uuidString
        let deferred = state.receive(first, mayExpand: false)
        #expect(!deferred && !state.isExpanded)
        let unchanged = state.receive(first, mayExpand: true)
        #expect(!unchanged && !state.isExpanded)
        state.isExpanded = true
        let restored = state.receive(nil, mayExpand: true)
        #expect(restored && !state.isExpanded)
        let next = state.receive(second, mayExpand: true)
        #expect(!next && state.isExpanded)
        let dismissed = state.receive(nil, mayExpand: false)
        #expect(dismissed)
    }

    @Test("The native draft, selection and editor identity survive question presentation")
    func retainsNativeDraft() async throws {
        _ = NSApplication.shared
        let conversation = UUID()
        var draft = "尚未发送的草稿，保留选区。"
        var focused = false
        var answers: [String: AgentChatQuestionAnswer] = [:]
        var sent = 0
        var requestExpansions = 0
        let questions: [AgentChatQuestion] = [
            .init(
                id: "focus", prompt: "先检查哪一部分？",
                options: [
                    .init(label: "原文依据", description: "核对所选材料中的措辞。"),
                    .init(label: "论证结构", description: "检查前提与结论的关系。"),
                ], allowsOther: true, isSecret: false)
        ]
        func content(_ requestID: String?, scheme: ColorScheme) -> some View {
            VStack {
                Text("正在核对所选材料。你可以继续阅读上方的对话。")
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                Spacer()
                AgentChatInputDock(
                    requestID: requestID, requestTitle: "回答问题", requestCount: requestID == nil ? 0 : 1,
                    isActive: true, isReadingHistory: false, isEditingDraft: false,
                    composerIsFocused: Binding(get: { focused }, set: { focused = $0 }),
                    onRequestExpanded: { requestExpansions += 1 }
                ) {
                    if requestID == "approval" {
                        AgentChatRuntimeApprovalView(
                            request: .init(
                                kind: .network, command: nil, cwd: nil, environmentID: nil, reason: nil,
                                networkHost: "example.org", networkProtocol: "https", permissions: nil,
                                files: [], grantRoot: nil, grants: [.once], rejection: .decline),
                            decision: nil, failure: nil, stop: {}, respond: { _ in })
                    } else if requestID != nil {
                        AgentChatQuestionForm(
                            questions: questions, answers: Binding(get: { answers }, set: { answers = $0 }),
                            isSubmitting: false, failure: nil, stop: {}, reply: {}, skip: {})
                    }
                } composer: {
                    AgentChatComposerInput(
                        text: Binding(get: { draft }, set: { draft = $0 }),
                        isFocused: Binding(get: { focused }, set: { focused = $0 }), conversationID: conversation,
                        isEnabled: true, submit: { sent += 1 })
                    HStack {
                        Image(systemName: "plus")
                        Spacer()
                        AgentChatComposerActionButton(
                            state: .ready, canSend: true, queuesInput: false,
                            submit: { sent += 1 }, submitAlternate: { sent += 1 }, stop: {})
                    }
                }
            }.frame(width: 340, height: 600)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, scheme)
        }
        let host = NSHostingView(rootView: content(nil, scheme: .light))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func editors(_ view: NSView) -> [AgentChatComposerHost] {
            (view as? AgentChatComposerHost).map { [$0] } ?? view.subviews.flatMap { editors($0) }
        }
        for _ in 0..<4 {
            await Task.yield()
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
        }
        let editor = try #require(editors(host).first)
        let range = NSRange(location: 2, length: 4)
        editor.editor.setSelectedRange(range)
        for scheme in [ColorScheme.light, .dark] {
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .accessibilityHighContrastDarkAqua)
            for requestID in ["question", "approval", Optional<String>.none] {
                host.rootView = content(requestID, scheme: scheme)
                for _ in 0..<8 {
                    await Task.yield()
                    window.layoutIfNeeded()
                    host.layoutSubtreeIfNeeded()
                }
                #expect(editors(host).first === editor)
                #expect(editor.editor.string == draft && draft == "尚未发送的草稿，保留选区。")
                #expect(editor.editor.selectedRange() == range)
                #expect(sent == 0)
                if requestID != nil { #expect(requestExpansions > 0) }
                if ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1" {
                    try await Task.sleep(for: .milliseconds(100))
                    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:])).write(
                        to:
                            repository.appendingPathComponent(
                                ".build/chat-input-dock/\(scheme == .light ? "light" : "dark")-\(requestID ?? "draft").png"))
                }
            }
        }
    }
}
