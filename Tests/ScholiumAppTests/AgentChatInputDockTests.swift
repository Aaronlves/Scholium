import AppKit
import ScholiumContracts
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Chat input transforms into requests", .serialized)
@MainActor
struct AgentChatInputDockTests {
  @Test("Request presentation defers while the researcher is occupied and restores the draft after resolution")
  func presentationLifecycle() {
    var state = AgentChatInputDockState()
    let first = UUID().uuidString, second = UUID().uuidString
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
    let questions: [AgentChatQuestion] = [.init(id: "focus", prompt: "先检查哪一部分？", options: [
      .init(label: "原文依据", description: "核对所选材料中的措辞。"),
      .init(label: "论证结构", description: "检查前提与结论的关系。")], allowsOther: true, isSecret: false)]
    func content(_ requestID: String?, scheme: ColorScheme) -> some View {
      VStack {
        Text("正在核对所选材料。你可以继续阅读上方的对话。")
          .frame(maxWidth: .infinity, alignment: .leading).padding()
        Spacer()
        AgentChatInputDock(requestID: requestID, requestTitle: "回答问题", requestCount: requestID == nil ? 0 : 1,
          isActive: true, isReadingHistory: false, isEditingDraft: false,
          composerIsFocused: Binding(get: { focused }, set: { focused = $0 })) {
            if requestID != nil {
              AgentChatQuestionForm(questions: questions, answers: Binding(get: { answers }, set: { answers = $0 }),
                isSubmitting: false, failure: nil, stop: {}, reply: {}, skip: {})
            }
          } composer: {
            AgentChatComposerInput(text: Binding(get: { draft }, set: { draft = $0 }),
              isFocused: Binding(get: { focused }, set: { focused = $0 }), conversationID: conversation,
              isEnabled: true, submit: { sent += 1 })
            HStack { Image(systemName: "plus"); Spacer(); Button("Send") { sent += 1 } }
          }
      }.frame(width: 340, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, scheme)
    }
    let host = NSHostingView(rootView: content(nil, scheme: .light))
    host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    func editors(_ view: NSView) -> [AgentChatComposerHost] {
      (view as? AgentChatComposerHost).map { [$0] } ?? view.subviews.flatMap { editors($0) }
    }
    for _ in 0..<4 { await Task.yield(); window.layoutIfNeeded(); host.layoutSubtreeIfNeeded() }
    let editor = try #require(editors(host).first)
    let range = NSRange(location: 2, length: 4)
    editor.editor.setSelectedRange(range)
    for scheme in [ColorScheme.light, .dark] {
      window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      for requestID in [UUID().uuidString, Optional<String>.none] {
        host.rootView = content(requestID, scheme: scheme)
        for _ in 0..<8 { await Task.yield(); window.layoutIfNeeded(); host.layoutSubtreeIfNeeded() }
        #expect(editors(host).first === editor)
        #expect(editor.editor.string == draft && draft == "尚未发送的草稿，保留选区。")
        #expect(editor.editor.selectedRange() == range)
        #expect(sent == 0)
        if ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1" {
          try await Task.sleep(for: .milliseconds(100))
          let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
          let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          try #require(bitmap.representation(using: .png, properties: [:])).write(to:
            repository.appendingPathComponent(".build/chat-input-dock/\(scheme == .light ? "light" : "dark")-\(requestID == nil ? "draft" : "question").png"))
        }
      }
    }
  }
}
