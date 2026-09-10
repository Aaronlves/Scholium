import AppKit
import ScholiumContracts
import ScholiumApplication
import SwiftUI
import Testing

@testable import ScholiumApp

/// Opt-in offscreen renders for visual inspection. No UI automation or ordered windows.
@Suite("Chat presentation renders", .serialized)
@MainActor
struct AgentChatVisualEvidenceTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderReplySurfaces() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let first = AgentChatReference.url(noteID: UUID()), second = AgentChatReference.url(noteID: UUID())
    let text = "[QA Topic](\(first)) [QA Work](\(second)) [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials) [PDF](../paper.pdf)"
    let process = [AgentChatMessage(role: .assistant, text: "已读取三篇材料，正在核对引用。", phase: .commentary)]
    for scheme in [ColorScheme.light, .dark] {
      let content = VStack(alignment: .leading, spacing: 20) {
        AgentChatProcessView(messages: process, isActive: false, hasFinalAnswer: true, forceExpanded: false,
          status: .init(state: .completed, timing: .init(durationMilliseconds: 38_500)), animates: false) {
          AgentChatMarkdown(text: $0.text)
        }
        AgentChatMarkdown(text: "这是一条用于检查排版的最终回复。保留 **原文依据** 与解释的区别，支持中文和 English 的自然换行。\n\n- 原文依据\n- 解释与评价\n\n| 材料 | 作用 |\n|---|---|\n| 原文 | 核对引文 |\n| 笔记 | 保留讨论 |\n\n可以跨段连续选取。", quoteSelection: { _ in })
        AgentChatReplyQuoteCard(quote: .init(conversationID: UUID(), messageID: "fixture",
          text: "原文依据与解释的区别"), openOriginal: {}, remove: {})
        AgentChatReplyActions(text: text, openNote: { _ in },
          context: .init(reply: .init(role: .assistant, text: text), history: []),
          openAttachment: { _ in }, previewMaterial: { _ in throw AgentChatNoteMaterialError.unavailable })
        Divider()
        AgentChatSourcesView(sources: AgentChatReplySource.collect(text), close: {}, open: { _ in })
      }.padding().frame(width: 350)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = host.appearance
      defer { window.contentView = nil; window.close() }
      window.contentView = host; window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent("reply-surfaces-\(scheme == .light ? "light" : "dark").png"))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderTurnStates() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/chat-motion-renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (index, fixture) in [(ColorScheme.light, "zh-Hans", 300.0), (.dark, "zh-Hans", 420.0),
      (.light, "en", 420.0), (.dark, "en", 300.0)].enumerated() {
      let (scheme, language, width) = fixture
      let content = VStack(alignment: .leading, spacing: 20) {
        ForEach(Array([AgentChatTurnPresentation.State.reading, .working, .responding,
          .waitingForInput, .waitingForApproval, .completed, .interrupted, .failed, .uncertain].enumerated()), id: \.offset) { _, state in
          AgentChatTurnStatus(presentation: .init(state: state,
            timing: .init(startedAt: Date(timeIntervalSinceNow: -12), durationMilliseconds: 38_500)), animates: false)
        }
        Divider()
        AgentChatMarkdown(text: "这一区分还需要结合上下文核对。The distinction needs further support.\n\n**原文与解释**\n\n- 保留原文措辞。\n- 将重构与原文明说的理由区分开。")
          .foregroundStyle(.primary)
      }.padding().frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: language))
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = host.appearance
      defer { window.contentView = nil; window.close() }
      window.contentView = host; window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent("turn-states-\(index).png"))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderConcurrentConversations() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/render-fixture-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
    }
    try await wait { controller.isLoaded }
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.connectionState == .ready && controller.account != nil }
    controller.rename("原文与注释比较")
    controller.editDraft("hold approval")
    controller.send()
    try await wait { !controller.approvals.isEmpty }
    controller.newConversation()
    controller.rename("情绪与理由：相关文献")
    controller.editDraft("hold activity")
    controller.send()
    try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
    controller.newConversation()
    controller.rename("反对意见梳理")
    controller.editDraft("capabilities")
    controller.send()
    try await wait { controller.state == .ready && !controller.isBusy && controller.selected?.pendingMessageID == nil }
    let original = try #require(controller.selectedID)
    let turn = try #require(controller.branchPoints.first?.turnID)
    controller.branch(through: turn)
    try await wait { controller.selectedID != original && !controller.isBusy }
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
      let content = AgentChatView(controller: controller, isVisible: false, addSelection: {},
        noteChoices: [], addNote: { _, _ in },
        openReference: { _ in false }, openAttachment: { _ in }, showInLibrary: { _ in },
        showChanges: { _ in }, showConversationChanges: { _ in })
        .frame(width: 340, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent(scheme == .light ? "conversations-light.png" : "conversations-dark.png"))
    }
    await controller.disconnect()
  }

  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition() {
      try #require(ContinuousClock.now < deadline, "Fixture did not reach its expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderNotePicker() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let notes: [WorkspaceCatalogNote] = [
      ("原文与解释：情绪的理由", VaultRole.sourceCorpus),
      ("Reasons and the limits of interpretation", VaultRole.topicKnowledge),
      ("Chapter 2 — Objections and Replies", VaultRole.draftProject)
    ].map { title, role in
      .init(reference: .init(vaultID: UUID(), vaultName: role.displayName, vaultRole: role,
        relativePath: "Research/\(title).md", stableNoteID: UUID().uuidString), title: title,
        fingerprint: .init(content: "Synthetic source"), validationWarnings: [])
    }
    for empty in [false, true] {
      for scheme in [ColorScheme.light, .dark] {
        let content = AgentChatNotePicker(notes: empty ? [] : notes, add: { _ in })
          .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        window.contentView = host
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("note-picker-\(empty ? "empty" : "populated")-\(scheme == .light ? "light" : "dark").png"))
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderLocalMaterials() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for failed in [false, true] {
      let id = UUID()
      let material = AgentChatLocalMaterial(id: id, source: .file(URL(fileURLWithPath: "/Fixture/Research/原文与解释.pdf")),
        storedFileName: "\(id).pdf", fingerprint: .init(content: "synthetic"), kind: .pdf,
        pages: failed ? [] : [.init(number: 1, text: "Synthetic source passage.\n\nA distinction between the source and its interpretation."),
          .init(number: 2, text: "")], issue: failed ? .noText : nil)
      for scheme in [ColorScheme.light, .dark] {
        let content = AgentChatLocalMaterialDetails(material: material, isOpening: false, previewError: nil, open: {}, replace: {})
          .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("local-material-\(failed ? "failed" : "pages")-\(scheme == .light ? "light" : "dark").png"))
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderPDFPageSelection() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for invalid in [false, true] {
      for scheme in [ColorScheme.light, .dark] {
        let content = AgentChatPDFPagesForm(fileName: "原文与解释.pdf", pageCount: 12,
          selection: .constant(invalid ? "1–99" : "2–5, 8"),
          error: invalid ? "Enter valid PDF page numbers, such as 1–5, 8." : nil,
          isPreparing: false, canUse: true, use: {}, cancel: {})
          .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("pdf-pages-\(invalid ? "invalid" : "selection")-\(scheme == .light ? "light" : "dark").png"))
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderCapturedImageMaterial() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for origin in [AgentChatLocalMaterial.CaptureOrigin.clipboard, .drop] {
      let id = UUID()
      let material = AgentChatLocalMaterial(id: id, source: .imageCapture(origin), storedFileName: "\(id).png",
        fingerprint: .init(content: "fixture image"), kind: .image,
        capturedFileName: "\(id).tiff", capturedFingerprint: .init(content: "fixture bitmap"))
      for scheme in [ColorScheme.light, .dark] {
        let content = AgentChatLocalMaterialDetails(material: material, isOpening: false, previewError: nil, open: {}, replace: {})
          .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("\(origin.rawValue)-material-\(scheme == .light ? "light" : "dark").png"))
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderQuestionForm() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let questions: [AgentChatQuestion] = [
      .init(id: "approach", prompt: "我们从哪里展开这段讨论？", options: [
        .init(label: "比较原文", description: "先核对两处原文，再讨论解释上的差异。"),
        .init(label: "检查反对意见", description: "检验这一反对意见是否击中论证的前提。")], allowsOther: true, isSecret: false),
      .init(id: "detail", prompt: "需要特别关注哪一点？", options: [], allowsOther: false, isSecret: false)]
    for state in ["empty", "custom", "pending", "tool"] {
      for scheme in [ColorScheme.light, .dark] {
        let answers: [String: AgentChatQuestionAnswer] = state == "empty" ? [:] : [
          "approach": .text("先区分作者的主张与我们的重构。"), "detail": .text("保留原文措辞，标明尚不能确定的部分。")]
        let content = AgentChatQuestionForm(questions: questions, answers: .constant(answers),
          isSubmitting: state == "pending", failure: nil,
          toolContext: state == "tool" ? "fixture_library · choose_source" : nil,
          technicalDetail: state == "tool" ? "Synthetic tool arguments" : nil, reply: {}, skip: {})
          .frame(width: 340).background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("questions-\(state)-\(scheme == .light ? "light" : "dark").png"))
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderUpdateComparison() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/comparison-render-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let before = Data("---\r\nsummary: 'Synthetic fixture'\r\n---\r\n\r\n# 原文与解释\r\n\r\n这里记录原有的解释。\r\n\r\n这段引文保持不变。\r\n".utf8)
    let after = Data("---\r\nsummary: 'Synthetic fixture'\r\n---\r\n\r\n# 原文与解释\r\n\r\n这里区分原文与我们的重构。\r\n尚不能确定的部分保留为问题。\r\n\r\n这段引文保持不变。\r\n".utf8)
    let preview = AgentNoteUpdatePreview(noteID: UUID(), relativePath: "Topics/原文与解释.md",
      comparison: try ExactSourceComparisonBuilder.build(startingData: before, endingData: after,
        startingRevision: .init(data: before), endingRevision: .init(data: after)))
    let controller = AgentChatController(triptychID: UUID(), root: root, previewUpdate: { _ in preview }) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { controller.isLoaded }
    let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
    try await wait { controller.account != nil && controller.state == .ready }
    controller.editDraft("hold proposed edit"); controller.send()
    try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
    let token = try #require(controller.token)
    let pending = Task { await controller.handle(.init(tool: .updateNote, conversationToken: token, runtimeContext: controller.runtimeContext(for: token))) }
    try await wait { !controller.approvals.isEmpty }
    let approval = try #require(controller.approvals.first)
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
      let content = AgentChatUpdateComparisonSheet(controller: controller, requestID: approval.id, preview: preview)
        .frame(width: 800, height: 600).environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent("update-comparison-\(scheme == .light ? "light" : "dark").png"))
    }
    await controller.disconnect()
    #expect(await pending.value.error != nil && !controller.isAwaitingDecision(approval.id))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderChildInspection() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
      let root = repository.appendingPathComponent(".build/agent-chat-evolution/child-render-\(UUID())")
      defer { try? FileManager.default.removeItem(at: root) }
      let parent = AgentChatController(triptychID: UUID(), root: root) { request in
        try! .init(requestID: request.requestID, result: .object([:]))
      }
      try await wait { parent.isLoaded }
      let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
      parent.connect(executable: fixture, home: parent.runtimeHome, cli: fixture)
      try await wait { parent.account != nil && parent.state == .ready }
      parent.rename("原文、解释与反对意见")
      parent.editDraft("hold delegation paginated-child"); parent.send()
      try await wait { parent.selected?.messages.contains { $0.activity?.delegation != nil } == true }
      let record = try #require(parent.selected?.messages.first { $0.activity?.delegation?.operation == .spawnAgent })
      let target = try #require(record.activity?.delegation?.targets.first?.id), owner = try #require(parent.selectedID)
      for state in ["ready", "pending", "received", "unavailable", "disconnected"] {
        let child = try #require(parent.childController(targetID: state == "unavailable" ? "unrelated" : target, messageID: record.id, in: owner))
        child.refresh(); try await wait { !child.isWorking && (child.snapshot != nil || child.error != nil) }
        child.editDraft("请保留页码，并检查第二处引文。")
        if state == "received" {
          parent.stop(in: owner); try await wait { parent.state(for: owner) == .ready }
          child.askParent(); try await wait { child.receipt != nil }
        } else if state == "pending" {
          try Data().write(to: parent.runtimeHome.appendingPathComponent("hold-child-stop"))
          child.stop(); try await wait { !child.isWorking }
        } else if state == "disconnected" { await parent.disconnect() }
        let content = AgentChatChildView(child: child, openReference: { _ in false }, close: {})
          .frame(width: 520, height: 560).background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        defer { window.contentView = nil; window.close() }
        window.contentView = host
        window.layoutIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("child-\(state)-\(scheme == .light ? "light" : "dark").png"))
        if state == "received" {
          let request = try #require(parent.selected?.messages.last { $0.role == .user })
          try await wait { parent.canBranch }
          parent.editInNewBranch(request.id)
          try await wait { parent.selectedID != owner && !parent.isBusy }
          let branch = try #require(parent.selectedID)
          #expect(await parent.selectNotification(.init(triptychID: parent.triptychID, conversationID: branch, event: .completed)))
          try await wait { !parent.isRefreshingHistory }
          let branchContent = AgentChatView(controller: parent, isVisible: false, addSelection: {},
            noteChoices: [], addNote: { _, _ in }, openReference: { _ in false }, openAttachment: { _ in }, showInLibrary: { _ in },
            showChanges: { _ in }, showConversationChanges: { _ in })
            .frame(width: 340, height: 700).background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
          let branchHost = NSHostingView(rootView: branchContent)
          branchHost.appearance = host.appearance
          branchHost.frame = NSRect(origin: .zero, size: branchHost.fittingSize)
          let branchWindow = NSWindow(contentRect: branchHost.frame, styleMask: [.titled], backing: .buffered, defer: false)
          branchWindow.isReleasedWhenClosed = false
          branchWindow.appearance = host.appearance
          defer { branchWindow.contentView = nil; branchWindow.close() }
          branchWindow.contentView = branchHost
          branchWindow.layoutIfNeeded(); await Task.yield(); branchHost.layoutSubtreeIfNeeded()
          let branchBitmap = try #require(branchHost.bitmapImageRepForCachingDisplay(in: branchHost.bounds))
          branchHost.cacheDisplay(in: branchHost.bounds, to: branchBitmap)
          try #require(branchBitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("child-branch-\(scheme == .light ? "light" : "dark").png"))
        }
        child.cancel()
      }
      await parent.disconnect()
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderNotificationDestination() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/notification-render-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { controller.isLoaded }
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.account != nil && controller.state == .ready }
    controller.rename("原文与解释")
    controller.editDraft("hold questions"); controller.send()
    try await wait { controller.approvals.count == 1 }
    let target = try #require(controller.selectedID)
    controller.newConversation()
    #expect(await controller.selectNotification(.init(triptychID: controller.triptychID, conversationID: target, event: .inputRequired)))
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
      let content = AgentChatView(controller: controller, isVisible: false, addSelection: {},
        noteChoices: [], addNote: { _, _ in }, openReference: { _ in false }, openAttachment: { _ in }, showInLibrary: { _ in },
        showChanges: { _ in }, showConversationChanges: { _ in })
        .frame(width: 340, height: 700).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      // Attach the hybrid composer to a native appearance context, never ordered.
      let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = host.appearance
      defer { window.contentView = nil; window.close() }
      window.contentView = host
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent("notification-destination-\(scheme == .light ? "light" : "dark").png"))
    }
    await controller.disconnect()
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderDelegation() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let report = AgentChatDelegation(operation: .spawnAgent, senderThreadID: "fixture-parent",
      prompt: "核对所提供的两处原文，保留页码与不确定之处。", targets: [
        .init(id: "fixture-child-a", path: "/root/source-check", state: .running),
        .init(id: "fixture-child-b", path: "/root/objection-check", state: .completed,
          message: "第二处原文尚无直接支持，应保留这一证据缺口。"),
        .init(id: "fixture-child-c", state: nil)])
    for scheme in [ColorScheme.light, .dark] {
      let content = AgentChatDelegationView(report: report, operationStatus: .completed)
        .padding().frame(width: 300).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent("delegation-\(scheme == .light ? "light" : "dark").png"))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderRuntimeApprovals() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let command = try CodexChatRuntimeApproval.parse(method: "item/commandExecution/requestApproval", params: [
      "command": .string("python3 inspect_sources.py --only supplied"), "cwd": .string("/Fixture/Research"),
      "reason": .string("读取所选论文中的参考文献。"), "availableDecisions": .array([.string("accept"), .string("acceptForSession"), .string("decline")])], item: nil)
    let permissions = try CodexChatRuntimeApproval.parse(method: "item/permissions/requestApproval", params: [
      "cwd": .string("/Fixture/Research"), "permissions": .object(["network": .object(["enabled": .bool(true)]),
        "fileSystem": .object(["entries": .array([
          .object(["access": .string("read"), "path": .object(["type": .string("path"), "path": .string("/Fixture/Sources")])]),
          .object(["access": .string("write"), "path": .object(["type": .string("glob_pattern"), "pattern": .string("/Fixture/Drafts/**/*.md")])]),
          .object(["access": .string("deny"), "path": .object(["type": .string("path"), "path": .string("/Fixture/Private")])])])])])], item: nil)
    let network = try CodexChatRuntimeApproval.parse(method: "item/commandExecution/requestApproval", params: [
      "command": .string("opaque network transport"), "networkApprovalContext": .object([
        "host": .string("sources.example.test:8443"), "protocol": .string("https")])], item: nil)
    let files = try CodexChatRuntimeApproval.parse(method: "item/fileChange/requestApproval", params: [:], item: .init(.object([
      "type": .string("fileChange"), "changes": .array([
        .object(["path": .string("/Fixture/原文与解释.md"), "kind": .object(["type": .string("update"), "move_path": .string("/Fixture/修订稿.md")]),
          "diff": .string("-旧的解释\n+区分原文与我们的重构\n")])])])))
    for (name, request, decision) in [("command", command, Optional<AgentChatRuntimeApproval.Decision>.none),
      ("permissions", permissions, nil), ("files", files, nil), ("network", network, nil), ("submitted", permissions, .session)] {
      for scheme in [ColorScheme.light, .dark] {
        let content = AgentChatRuntimeApprovalView(request: request.presentation, technicalDetail: "Synthetic runtime request",
          decision: decision, failure: nil, respond: { _ in })
          .frame(width: 300).background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans"))
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("runtime-approval-\(name)-\(scheme == .light ? "light" : "dark").png"))
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderMethodSettings() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/render-method-\(UUID())")
    let suite = "scholium.method-render.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
    }
    try await wait { controller.isLoaded }
    try FileManager.default.createDirectory(at: controller.runtimeHome, withIntermediateDirectories: true)
    try Data().write(to: controller.runtimeHome.appendingPathComponent("oauth-fixture"))
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }
    let folder = root.appendingPathComponent("research-methods")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    controller.capabilities.associate(folder, threadID: nil)
    try await wait { controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for kind in AgentChatToolConnection.Kind.allCases {
      var edit = try #require(controller.capabilities.editTool())
      edit.connection = .init(name: "research-catalog-\(kind.rawValue)", kind: kind,
        address: kind == .remote ? "https://example.invalid/mcp" : "/usr/bin/python3",
        arguments: kind == .local ? ["-m", "research_catalog"] : [],
        bearerTokenVariable: kind == .remote ? "RESEARCH_API_TOKEN" : "",
        environmentVariables: kind == .local ? ["RESEARCH_API_TOKEN"] : [])
      #expect(await controller.capabilities.saveTool(edit))
      try await wait { controller.capabilities.canConfigureTools }
      edit = try #require(controller.capabilities.editTool(named: edit.connection.name))
      for scheme in [ColorScheme.light, .dark] {
        let content = AgentChatToolEditor(capabilities: controller.capabilities, edit: edit)
          .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
          .write(to: output.appendingPathComponent("tool-editor-\(kind.rawValue)" + (scheme == .light ? "-light.png" : "-dark.png")))
      }
    }
    for pending in [false, true] {
      if pending {
        let server = try #require(controller.capabilities.tools.first { $0.name == "fixture-library" })
        controller.capabilities.signIn(server, threadID: nil) { _ in }
        try await wait { controller.capabilities.authorizationURL != nil }
      }
    for scheme in [ColorScheme.light, .dark] {
      let content = AgentChatCapabilitiesSettingsView(controller: controller, capabilities: controller.capabilities)
        .padding(20).frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent((pending ? "tool-auth-pending" : "methods") + (scheme == .light ? "-light.png" : "-dark.png")))
    }
    }
    await controller.disconnect()
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderFindControls() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
      let content = AgentChatFindBar(query: .constant("情绪与理由"), focusRequest: nil,
        position: 2, count: 12, move: { _ in }, dismiss: {})
        .frame(width: 280).padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: output.appendingPathComponent(scheme == .light ? "find-light.png" : "find-dark.png"))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1"))
  func renderRuntimeControls() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/renders")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = AgentChatModel(id: "fixture", model: "fixture", name: "Research Model",
      efforts: ["low", "medium", "high"], defaultEffort: "medium", isDefault: true,
      inputModalities: ["text", "image"])
    let plan = AgentChatPlan(turnID: "fixture", explanation: nil, steps: [
      .init(step: "阅读所选原文", status: .completed),
      .init(step: "比较两种解释", status: .inProgress),
      .init(step: "核对引文位置", status: .pending),
    ])
    for scheme in [ColorScheme.light, .dark] {
      let content = VStack(alignment: .leading, spacing: 16) {
        AgentChatModelMenu(models: [model], preferences: .init(model: "fixture", effort: "high"),
          selectedModel: model, isEnabled: true, selectModel: { _ in }, selectEffort: { _ in })
        AgentChatPlanView(plan: plan)
        AgentChatActivityText(text: "已读取笔记 · 行动理由.md", isCurrent: false)
        AgentChatActivityText(text: "正在检索知识库 · 实践理性与行动理由之间的关系", isCurrent: true)
        AgentChatActivityDetails(activity: .init(kind: .command, status: .failed, source: .runtime,
          subject: "read fixture.md", detail: (1...40).map { "行 \($0)：合成输出，保留原始文本与错误。" }.joined(separator: "\n")))
        AgentChatActivityDetails(activity: .init(kind: .read, status: .completed, source: .scholium,
          subject: "示例材料", detail: "已读取选段。"))
        Divider()
        AgentChatContextView(usage: .init(lastTurnTokens: 12480, totalTokens: 45900, capacity: 128000),
          quotas: [.init(id: "fixture", name: "Research", primary: .init(usedPercent: 25,
            durationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1788825600)), secondary: nil)],
          quotaError: nil, isRefreshing: false, canRefresh: true, canCompact: true,
          compact: {}, refresh: {})
      }
      .padding(20).frame(width: 380)
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, scheme)
      let host = NSHostingView(rootView: content)
      host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      try data.write(to: root.appendingPathComponent(scheme == .light ? "runtime-light.png" : "runtime-dark.png"))
    }
  }
}
