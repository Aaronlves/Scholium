import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat sidebar presentation lifecycle", .serialized)
@MainActor
struct AgentChatSidebarLifecycleTests {
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  @Test(
    "The mounted Chat shell changes native draft ownership and clears the previous conversation's Find",
    arguments: [false, true])
  func conversationSwitchKeepsDraftsAndResetsFind(reduceMotion: Bool) async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(".build/agent-chat-tests/sidebar-switch-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let firstID = try #require(controller.selectedID)
    let firstDraft = "First unsent draft "
    controller.editDraft(firstDraft)
    controller.newConversation()
    let secondID = try #require(controller.selectedID)
    controller.editDraft("第二个未发送草稿")

    let readerID = UUID()
    let host = NSHostingView(
      rootView: AgentChatView(
        controller: controller, transcriptReaderID: readerID, isVisible: true,
        addSelection: { _ in false },
        noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
        openAttachment: { _, _ in }, showChanges: { _ in },
        showConversationChanges: { _ in }
      )
      .environment(\.scholiumVisualEnvironmentOverride, .init(reduceMotion: reduceMotion)))
    let window = mount(host)
    defer {
      window.contentView = nil
      window.close()
    }
    #expect(
      controller.transcriptReaders[readerID] == nil,
      "The conversation list is not an active conversation")
    #expect(
      await controller.selectNotification(
        .init(triptychID: controller.triptychID, conversationID: firstID, event: .inputRequired)))
    try await settle(host) { composer(in: host)?.conversationID == firstID }
    #expect(controller.transcriptReaders[readerID] == firstID)
    let first = try #require(composer(in: host))
    #expect(first.editor.string == firstDraft)

    // Exercise the real composer command route instead of reaching into
    // the shell's private presentation state to display Find.
    first.editor.setSelectedRange(NSRange(location: firstDraft.utf16.count, length: 0))
    first.editor.insertText("/find", replacementRange: first.editor.selectedRange())
    try await settle(host) {
      first.completion?.candidates.contains {
        if case .find = $0.action { return true }
        return false
      } == true
        && first.completion?.candidateQuery == first.completion?.query
    }
    let completion = try #require(first.completion)
    let candidate = try #require(
      completion.candidates.first {
        if case .find = $0.action { return true }
        return false
      })
    completion.accept(candidate)
    try await settle(host) { findField(in: host) != nil }
    let query = try #require(findField(in: host))
    query.stringValue = "first-only query"
    try #require(query.target as? ContextSearchField.Coordinator).searchChanged(query)
    try await settle(host) { controller.selected?.draft == firstDraft }
    let firstSelection = first.editor.selectedRange()
    let firstUndo = try #require(first.editor.undoManager)

    #expect(
      await controller.selectNotification(
        .init(triptychID: controller.triptychID, conversationID: secondID, event: .inputRequired)))
    try await settle(host) {
      composer(in: host)?.conversationID == secondID && findField(in: host) == nil
    }
    let second = try #require(composer(in: host))
    #expect(second.editor.string == "第二个未发送草稿")
    #expect(second !== first && first.completion == nil)
    second.editor.setSelectedRange(NSRange(location: second.editor.string.utf16.count, length: 0))
    second.editor.insertText("，补充", replacementRange: second.editor.selectedRange())
    try await settle(host) { controller.selected?.draft == "第二个未发送草稿，补充" }

    #expect(
      await controller.selectNotification(
        .init(triptychID: controller.triptychID, conversationID: firstID, event: .inputRequired)))
    try await settle(host) {
      composer(in: host)?.conversationID == firstID && findField(in: host) == nil
    }
    #expect(composer(in: host)?.editor.string == firstDraft)
    #expect(composer(in: host)?.editor === first.editor)
    #expect(composer(in: host)?.editor.selectedRange() == firstSelection)
    #expect(composer(in: host)?.editor.undoManager === firstUndo)
    #expect(controller.conversations.first { $0.id == secondID }?.draft == "第二个未发送草稿，补充")
    #expect(controller.conversations.allSatisfy { $0.messages.isEmpty })
    #expect(controller.connectionState == .disconnected)
    try await controller.flushPersistence()
  }

  @Test(
    "The Chat shell releases hidden readers while preserving native draft selection and Undo",
    arguments: [false, true])
  func shellVisibilityReleasesReadersAndKeepsNativeDraft(reduceMotion: Bool) async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(
      ".build/agent-chat-tests/shell-reader-release-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let triptychID = UUID()
    var conversation = AgentChatConversation(triptychID: triptychID)
    conversation.draft = "Unsent shell draft 中文 🦉 "
    conversation.messages = (0..<2).flatMap { index in
      [
        AgentChatMessage(
          id: "question-\(index)", role: .user, text: "Synthetic question \(index). 中文。"),
        AgentChatMessage(
          id: "reply-\(index)", role: .assistant,
          text: "A small **synthetic reply \(index)**. 中文 and English.", phase: .finalAnswer),
      ]
    }
    let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
    try await storage.save([conversation])
    let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let readerID = UUID()
    func shell(visible: Bool) -> some View {
      AgentChatView(
        controller: controller, transcriptReaderID: readerID, isVisible: visible,
        addSelection: { _ in false }, noteChoices: [], prepareNotes: { _ in { _ in } },
        openReference: { _ in false }, openAttachment: { _, _ in }, showChanges: { _ in },
        showConversationChanges: { _ in }
      )
      .environment(\.scholiumVisualEnvironmentOverride, .init(reduceMotion: reduceMotion))
    }
    func readers(in view: NSView) -> [AgentChatReadWebView] {
      (view as? AgentChatReadWebView).map { [$0] } ?? view.subviews.flatMap { readers(in: $0) }
    }
    func nativeReaders(in view: NSView) -> [AgentChatNativeParagraphView] {
      (view as? AgentChatNativeParagraphView).map { [$0] }
        ?? view.subviews.flatMap { nativeReaders(in: $0) }
    }
    func allReaders(in view: NSView) -> [NSView] {
      if view is WKWebView || view is AgentChatNativeParagraphView { return [view] }
      return view.subviews.flatMap { allReaders(in: $0) }
    }
    let host = NSHostingView(rootView: shell(visible: true))
    let window = mount(host)
    defer {
      window.contentView = nil
      window.close()
    }
    func detailIsReady() -> Bool {
      let mounted = readers(in: host)
      return mounted.count == 2 && nativeReaders(in: host).count == 2
        && mounted.allSatisfy {
          $0.accessibilityIdentifier() == "scholium.renderedDocument.chat-reply"
            && !$0.isLoading && $0.bounds.width > 0 && $0.bounds.height > 0
        }
        && composer(in: host)?.conversationID == conversation.id
        && composer(in: host)?.editor.isEditable == true
    }
    #expect(
      await controller.selectNotification(
        .init(triptychID: triptychID, conversationID: conversation.id, event: .inputRequired)))
    try await settle(host) { detailIsReady() }
    #expect(controller.transcriptReaders[readerID] == conversation.id)
    let editor = try #require(composer(in: host)?.editor)
    let undo = try #require(editor.undoManager)
    let originalDraft = conversation.draft
    // Open Find through the native composer route before establishing the
    // independent typing Undo group whose lifetime is checked below.
    do {
      let native = try #require(composer(in: host))
      editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
      editor.insertText("/find", replacementRange: editor.selectedRange())
      try await settle(host) {
        native.completion?.candidates.contains {
          if case .find = $0.action { return true }
          return false
        } == true && native.completion?.candidateQuery == native.completion?.query
      }
      let completion = try #require(native.completion)
      let candidate = try #require(
        completion.candidates.first {
          if case .find = $0.action { return true }
          return false
        })
      completion.accept(candidate)
    }
    try await settle(host) {
      findField(in: host) != nil && editor.string.utf8.elementsEqual(originalDraft.utf8)
    }
    let findQuery = "synthetic reply 1"
    do {
      let field = try #require(findField(in: host))
      field.stringValue = findQuery
      try #require(field.target as? ContextSearchField.Coordinator).searchChanged(field)
    }
    try await settle(host) {
      guard let field = findField(in: host), let fieldEditor = field.currentEditor() else {
        return false
      }
      return field.stringValue == findQuery && window.firstResponder === fieldEditor
        && detailIsReady()
    }
    let retainedDraft = originalDraft + "\nAdded cafe\u{301} — 未发送。"
    undo.beginUndoGrouping()
    editor.insertText(
      "\nAdded cafe\u{301} — 未发送。",
      replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
    undo.endUndoGrouping()
    editor.breakUndoCoalescing()
    editor.setSelectedRange(NSRange(location: 2, length: 4))
    let selection = editor.selectedRange()
    try #require(undo.canUndo)
    try await settle(host) {
      controller.selected?.draft.utf8.elementsEqual(retainedDraft.utf8) == true
    }
    #expect(editor.string.utf8.elementsEqual(retainedDraft.utf8))
    // Keep only weak reader boxes across removal. A test-owned strong array
    // would prevent the release that this actual-shell contract requires.
    let departedReaders = allReaders(in: host).map(WeakSidebarReader.init)
    try #require(departedReaders.count == 4)
    host.rootView = shell(visible: false)
    try await settle(host) {
      allReaders(in: host).isEmpty && departedReaders.allSatisfy { $0.view == nil }
        && editor.window == nil && controller.transcriptReaders[readerID] == nil
        && findField(in: host) == nil
    }
    #expect(composer(in: host) == nil)
    #expect(editor.string.utf8.elementsEqual(retainedDraft.utf8))
    #expect(controller.selected?.draft.utf8.elementsEqual(retainedDraft.utf8) == true)
    #expect(editor.selectedRange() == selection && editor.undoManager === undo && undo.canUndo)

    host.rootView = shell(visible: true)
    try await settle(host) {
      guard let field = findField(in: host), let fieldEditor = field.currentEditor() else {
        return false
      }
      return detailIsReady() && field.stringValue == findQuery && field.isEnabled
        && window.firstResponder === fieldEditor
    }
    #expect(
      departedReaders.allSatisfy { $0.view == nil },
      "Every reader must belong to the fresh detail lifetime.")
    #expect(composer(in: host)?.editor === editor)
    #expect(editor.string.utf8.elementsEqual(retainedDraft.utf8))
    #expect(controller.selected?.draft.utf8.elementsEqual(retainedDraft.utf8) == true)
    #expect(editor.selectedRange() == selection && editor.undoManager === undo && undo.canUndo)
    #expect(controller.transcriptReaders[readerID] == conversation.id)
    #expect(controller.selected?.messages == conversation.messages)
    #expect(controller.connectionState == .disconnected)
    undo.undo()
    #expect(editor.string.utf8.elementsEqual(originalDraft.utf8))
    #expect(controller.selected?.draft.utf8.elementsEqual(originalDraft.utf8) == true)
    try #require(undo.canRedo)
    undo.redo()
    #expect(editor.string.utf8.elementsEqual(retainedDraft.utf8))
    #expect(controller.selected?.draft.utf8.elementsEqual(retainedDraft.utf8) == true)
    try await controller.flushPersistence()
    let saved = try #require(try await storage.load().first { $0.id == conversation.id })
    #expect(saved.draft.utf8.elementsEqual(retainedDraft.utf8))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try encoder.encode(saved.messages) == encoder.encode(conversation.messages))
  }

  @Test(
    "A mounted reply jump is consumed once and cannot replace a later reading anchor on remount")
  func consumedReplyNavigationDoesNotReplayOnRemount() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(
      ".build/agent-chat-tests/consumed-reply-navigation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let conversationID = try #require(controller.selectedID)
    controller.update {
      $0.draft = "Unsent navigation draft 中文。"
      $0.messages = (0..<2).flatMap { index in
        [
          AgentChatMessage(
            id: "question-\(index)", role: .user, text: "Synthetic question \(index)."),
          AgentChatMessage(
            id: "reply-\(index)", role: .assistant, text: "Synthetic reply \(index).",
            phase: .finalAnswer),
        ]
      }
    }
    let messages = try #require(controller.selected?.messages)
    let projection = AgentChatTimelineProjection(messages)
    let session = AgentChatReadingSession()
    let native = AgentChatComposerSession(conversationID: conversationID)
    let presentation = AgentChatDetailPresentation()
    var navigation: AgentChatReplyNavigation? = .init(
      conversationID: conversationID, messageID: "question-0")
    func detail() -> some View {
      AgentChatConversationDetailView(
        controller: controller, isVisible: true, addSelection: { _ in false },
        noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
        openAttachment: { _, _ in }, showChanges: { _ in }, showConversationChanges: { _ in },
        presentation: presentation, readingSession: session, nativeSession: native,
        focusRequest: nil, consumeFocusRequest: { _ in },
        replyNavigation: Binding(get: { navigation }, set: { navigation = $0 }),
        openReply: { _ in }, showList: {}, newConversation: {}, didRestoreConversation: {},
        renameConversation: { _ in }, showAccountUsage: {})
    }
    let host = NSHostingView(rootView: AnyView(detail()))
    let window = mount(host)
    defer {
      window.contentView = nil
      window.close()
    }
    try await settle(host) {
      navigation == nil && session.isInitialTranscriptReady && session.viewportRequest == nil
        && session.anchor?.id == "question-0"
    }
    // Model a subsequent explicit reading intent through the existing
    // session API; this test does not claim native scroll geometry proof.
    session.navigate(to: "reply-1", in: projection.ids)
    try await settle(host) { session.anchor?.id == "reply-1" && session.viewportRequest == nil }
    let laterAnchor = try #require(session.anchor)
    host.rootView = AnyView(Color.clear)
    try await settle(host) { session.viewport == nil && native.host.window == nil }
    #expect(navigation == nil && session.anchor == laterAnchor)
    host.rootView = AnyView(detail())
    try await settle(host) { session.isInitialTranscriptReady && session.viewportRequest == nil }
    #expect(
      navigation == nil,
      "A completed link request must not survive into a new presentation lifetime.")
    #expect(session.anchor == laterAnchor && session.isRetainingPosition)
    #expect(controller.selected?.messages == messages)
    #expect(native.host.editor.string == "Unsent navigation draft 中文。")
    try await controller.flushPersistence()
  }

  @Test(
    "An outgoing or hidden detail relinquishes focus and idle sheets while preserving queued writing, native draft and Undo"
  )
  func outgoingDetailKeepsItsConversationIdentity() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(
      ".build/agent-chat-tests/outgoing-identity-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let firstID = try #require(controller.selectedID)
    controller.editDraft("First native draft")
    controller.newConversation()
    let secondID = try #require(controller.selectedID)
    controller.editDraft("Second independent draft")
    controller.select(firstID)
    let nativeSession = AgentChatComposerSession(conversationID: firstID)
    let presentation = AgentChatDetailPresentation()
    let readingSession = AgentChatReadingSession()
    func detail(visible: Bool) -> AgentChatConversationDetailView {
      AgentChatConversationDetailView(
        controller: controller, isVisible: visible, addSelection: { _ in false },
        noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
        openAttachment: { _, _ in }, showChanges: { _ in },
        showConversationChanges: { _ in }, presentation: presentation,
        readingSession: readingSession, nativeSession: nativeSession,
        focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil),
        openReply: { _ in }, showList: {},
        newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
        showAccountUsage: {})
    }
    let host = NSHostingView(rootView: AnyView(detail(visible: true)))
    let window = mount(host)
    defer {
      presentation.notePickerTarget = nil
      presentation.queueEditTarget = nil
      if let sheet = window.attachedSheet {
        window.endSheet(sheet)
        sheet.orderOut(nil)
      }
      window.contentView = nil
      window.close()
    }
    try await settle(host) {
      nativeSession.host.window === window && nativeSession.host.editor.isEditable
    }
    let editor = nativeSession.host.editor
    let undo = try #require(editor.undoManager)
    undo.beginUndoGrouping()
    editor.insertText(
      " edited", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
    undo.endUndoGrouping()
    editor.breakUndoCoalescing()
    editor.setSelectedRange(NSRange(location: 2, length: 4))
    let retained = editor.string
    let selection = editor.selectedRange()
    try #require(undo.canUndo)
    presentation.showsFind = true
    presentation.findFocusRequest = UUID()
    try await settle(host) {
      guard let field = findField(in: host), let fieldEditor = field.currentEditor() else {
        return false
      }
      return field.isEnabled && window.firstResponder === fieldEditor
    }
    let find = try #require(findField(in: host))
    let findEditor = try #require(find.currentEditor())

    // Keep A's actual detail mounted while its observed controller selects B,
    // as happens during the outgoing page's navigation transition.
    controller.select(secondID)
    try await settle(host) {
      !editor.isEditable && !find.isEnabled && window.firstResponder !== findEditor
    }
    #expect(nativeSession.conversationID == firstID && nativeSession.host.conversationID == firstID)
    #expect(editor.string == retained && editor.selectedRange() == selection)
    #expect(editor.undoManager === undo && undo.canUndo)
    #expect(controller.conversations.first { $0.id == firstID }?.draft == retained)
    #expect(
      controller.conversations.first { $0.id == secondID }?.draft == "Second independent draft")
    controller.select(firstID)
    try await settle(host) { editor.isEditable && find.isEnabled }

    // The same native field also relinquishes focus when its current detail
    // becomes hidden, independently of the selected-conversation guard.
    try #require(window.makeFirstResponder(find))
    let resumedFindEditor = try #require(find.currentEditor())
    try #require(window.firstResponder === resumedFindEditor)
    // An idle picker is retained presentation state, not admitted material
    // work. Hiding Chat must remove its future keyboard/accessibility route.
    presentation.notePickerTarget = .init(id: firstID)
    #expect(presentation.notePickerTarget?.id == firstID)
    host.rootView = AnyView(detail(visible: false))
    try await settle(host) { !find.isEnabled && window.firstResponder !== resumedFindEditor }
    #expect(
      presentation.notePickerTarget?.id == nil,
      "A hidden retained Chat must dismiss its Note picker.")
    #expect(findField(in: host) === find)
    #expect(editor.string == retained && editor.selectedRange() == selection)
    #expect(editor.undoManager === undo && undo.canUndo)
    #expect(controller.conversations.first { $0.id == firstID }?.draft == retained)
    #expect(
      controller.conversations.first { $0.id == secondID }?.draft == "Second independent draft")
    // The sheet's writing belongs to its retained target. A presentation-
    // only dismissal must not consume text that may still need copying.
    let queueTarget = AgentChatQueueEditTarget(
      conversationID: firstID, message: .init(role: .user, text: "Original queued message"))
    queueTarget.text = "Unsent queued-message edits"
    queueTarget.unavailable = true
    presentation.queueEditTarget = queueTarget
    let hiddenQueue = detail(visible: false).queuedMessageEditorTarget
    #expect(hiddenQueue.wrappedValue?.id == nil)
    hiddenQueue.wrappedValue = nil
    #expect(presentation.queueEditTarget === queueTarget)
    #expect(queueTarget.text == "Unsent queued-message edits" && queueTarget.unavailable)
    #expect(detail(visible: true).queuedMessageEditorTarget.wrappedValue === queueTarget)
    // Test-owned dismissal keeps the following native Find restoration
    // independent of a queued-message modal or actual attached-sheet focus.
    presentation.queueEditTarget = nil
    host.rootView = AnyView(detail(visible: true))
    try await settle(host) { editor.isEditable && find.isEnabled }
    #expect(window.firstResponder === find.currentEditor())
    undo.undo()
    #expect(
      editor.string == "First native draft" && controller.selected?.draft == "First native draft")
    try await controller.flushPersistence()
  }

  @Test(
    "A hidden explicit focus intent is consumed once and a historical handoff never refocuses on visibility"
  )
  func visibilityUsesOnlyPendingFocusIntent() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(".build/agent-chat-tests/focus-intent-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let nativeSession = AgentChatComposerSession(conversationID: controller.selectedID)
    let presentation = AgentChatDetailPresentation()
    let readingSession = AgentChatReadingSession()
    var pendingFocus: UUID? = UUID()
    var consumed = 0
    func detail(visible: Bool) -> some View {
      AgentChatConversationDetailView(
        controller: controller, isVisible: visible, addSelection: { _ in false },
        noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
        openAttachment: { _, _ in }, showChanges: { _ in },
        showConversationChanges: { _ in }, presentation: presentation,
        readingSession: readingSession, nativeSession: nativeSession,
        focusRequest: pendingFocus,
        consumeFocusRequest: { id in
          if pendingFocus == id {
            pendingFocus = nil
            consumed += 1
          }
        }, replyNavigation: .constant(nil), openReply: { _ in }, showList: {}, newConversation: {},
        didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {})
    }
    let host = NSHostingView(rootView: AnyView(detail(visible: false)))
    let window = mount(host)
    defer {
      window.contentView = nil
      window.close()
    }
    try await settle(host) { nativeSession.host.window === window }
    #expect(consumed == 0 && pendingFocus != nil && !presentation.messageIsFocused)
    host.rootView = AnyView(detail(visible: true))
    try await settle(host) {
      consumed == 1 && pendingFocus == nil && window.firstResponder === nativeSession.host.editor
    }
    host.rootView = AnyView(detail(visible: false))
    try await settle(host) {
      !presentation.messageIsFocused && window.firstResponder !== nativeSession.host.editor
    }
    controller.contextPresentationID = UUID()
    host.rootView = AnyView(detail(visible: true))
    host.layoutSubtreeIfNeeded()
    #expect(consumed == 1 && !presentation.messageIsFocused)
    #expect(window.firstResponder !== nativeSession.host.editor)
    try await controller.flushPersistence()
  }

  @Test(
    "Remounting the same conversation restores its native reading anchor and refreshes retained Find results"
  )
  func detailRemountKeepsReadingAndRefreshesFind() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(
      ".build/agent-chat-tests/sidebar-remount-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
    do {
      try await settle {
        controller.canSend || (controller.account != nil && controller.state == .ready)
      }
      controller.editDraft(
        String(
          repeating: "Synthetic retained passage for native reading continuity. 中文合成测试文字。\n\n",
          count: 24))
      controller.send()
      try await settle {
        !controller.isBusy
          && controller.selected?.messages.contains { $0.role == .assistant } == true
      }
      let conversationID = try #require(controller.selectedID)
      let firstMessage = try #require(controller.selected?.messages.first { $0.role == .user })
      let presentation = AgentChatDetailPresentation()
      presentation.showsFind = true
      presentation.find.query = "retained"
      presentation.findFocusRequest = UUID()
      presentation.find.refresh(messages: controller.selected?.messages ?? [], reset: true)
      let originalMatches = presentation.find.messageIDs.count
      #expect(originalMatches == 1)
      let session = AgentChatReadingSession()
      let nativeSession = AgentChatComposerSession(conversationID: conversationID)

      func detail() -> some View {
        AgentChatConversationDetailView(
          controller: controller, isVisible: true, addSelection: { _ in false },
          noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
          openAttachment: { _, _ in }, showChanges: { _ in },
          showConversationChanges: { _ in }, presentation: presentation, readingSession: session,
          nativeSession: nativeSession,
          focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil),
          openReply: { _ in }, showList: {},
          newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
          showAccountUsage: {})
      }
      let host = NSHostingView(rootView: AnyView(detail()))
      let window = mount(host)
      defer {
        window.contentView = nil
        window.close()
      }
      try await settle(host) {
        guard let marker = session.markers[firstMessage.id]?.view,
          let scroll = marker.enclosingScrollView, let document = scroll.documentView
        else { return false }
        return document.frame.height > scroll.contentView.bounds.height + 300
          && abs(
            scroll.contentView.bounds.maxY - document.frame.height - scroll.contentInsets.bottom)
            < 1
          && findField(in: host) != nil
      }
      #expect(!session.isRetainingPosition)
      #expect(session.viewportRequest == nil)
      #expect(window.firstResponder === findField(in: host)?.currentEditor())
      session.pause()
      session.anchor = .init(id: firstMessage.id, offset: -120)
      session.viewport?.reconcile()
      let retainedAnchor = try #require(session.anchor)

      // This is the real detail's unmount/remount boundary, not an
      // assertion that the shell's Back button was exercised.
      host.rootView = AnyView(Color.clear)
      try await settle(host) { session.viewport == nil && composer(in: host) == nil }
      controller.editDraft("Another retained question while the detail is absent")
      controller.send()
      try await settle {
        !controller.isBusy && controller.selected?.messages.filter { $0.role == .user }.count == 2
      }
      #expect(presentation.find.messageIDs.count == originalMatches)
      controller.editDraft("Unsent draft after background completion")
      host.rootView = AnyView(detail())
      try await settle(host) {
        presentation.find.messageIDs.count == originalMatches + 1
          && composer(in: host)?.conversationID == conversationID
          && session.markers[firstMessage.id]?.view != nil
      }
      try await settle(host) {
        session.viewport?.reconcile()
        guard let marker = session.markers[retainedAnchor.id]?.view,
          let scroll = marker.enclosingScrollView, let document = scroll.documentView
        else { return false }
        let offset =
          marker.convert(marker.bounds, to: document).minY
          - scroll.contentView.bounds.minY - scroll.contentInsets.top
        return abs(offset - retainedAnchor.offset) < 2
      }
      #expect(session.isRetainingPosition)
      #expect(findField(in: host)?.stringValue == "retained")
      #expect(window.firstResponder === findField(in: host)?.currentEditor())
      #expect(composer(in: host)?.editor.string == "Unsent draft after background completion")
      try await controller.flushPersistence()
    } catch {
      await controller.disconnect()
      throw error
    }
    await controller.disconnect()
  }

  @Test("Cold entry hydrates Markdown readers without waiting for a native async-question row")
  func coldEntryWithNativeAsyncQuestion() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(
      ".build/agent-chat-tests/native-question-entry-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let conversationID = try #require(controller.selectedID)
    var question = AgentChatMessage(
      id: "native-question", role: .assistant, text: "Which passage should I compare?")
    question.asyncQuestion = .init(questions: [
      .init(
        id: "passage", prompt: "Which passage should I compare?", options: [], allowsOther: true,
        isSecret: false)
    ])
    controller.update {
      $0.messages = [
        .init(id: "request", role: .user, text: "Compare these two synthetic passages."),
        .init(
          id: "reply", role: .assistant, text: "A retained **synthetic reply**. 中文。",
          phase: .finalAnswer),
        question,
      ]
    }
    let session = AgentChatReadingSession()
    let native = AgentChatComposerSession(conversationID: conversationID)
    let host = NSHostingView(
      rootView: AgentChatConversationDetailView(
        controller: controller, isVisible: true, addSelection: { _ in false },
        noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
        openAttachment: { _, _ in }, showChanges: { _ in },
        showConversationChanges: { _ in }, presentation: AgentChatDetailPresentation(),
        readingSession: session, nativeSession: native,
        focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil),
        openReply: { _ in }, showList: {},
        newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
        showAccountUsage: {}))
    let window = mount(host)
    defer {
      window.contentView = nil
      window.close()
    }
    try await settle(host) {
      session.initialTranscriptPhase == .visible && session.viewportRequest == nil
    }
    func readerCount(in view: NSView) -> Int {
      (view is AgentChatReadWebView ? 1 : 0) + view.subviews.reduce(0) { $0 + readerCount(in: $1) }
    }
    func plainRequests(in view: NSView) -> [AgentChatNativeParagraphView] {
      (view as? AgentChatNativeParagraphView).map { [$0] }
        ?? view.subviews.flatMap { plainRequests(in: $0) }
    }
    #expect(readerCount(in: host) == 1)
    let requests = plainRequests(in: host)
    try #require(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.string.utf8.elementsEqual("Compare these two synthetic passages.".utf8))
    #expect(request.bounds.width > 0 && request.bounds.height > 0 && request.isSelectable)
    #expect(session.areReadersHydrated(["request", "reply"]))
    #expect(session.markers[question.id]?.view?.window === window)
    #expect(
      controller.selected?.messages.last?.asyncQuestion?.questions.first?.prompt == question.text)
    #expect(controller.connectionState == .disconnected)
  }

  @Test(
    "Hiding Chat dismisses Outline while retaining native readers, draft, focus context and reading position"
  )
  func retainedTranscriptSurvivesHiddenResize() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(
      ".build/agent-chat-tests/retained-resize-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let triptychID = UUID()
    var conversation = AgentChatConversation(triptychID: triptychID)
    conversation.draft = "Unsent Outline regression draft"
    conversation.messages = (0..<2).flatMap { index in
      [
        AgentChatMessage(
          id: "question-\(index)", role: .user, text: "Synthetic question \(index). 中文。"),
        AgentChatMessage(
          id: "reply-\(index)", role: .assistant,
          text: String(
            repeating: "A retained synthetic passage with **中文 and English**.\n\n", count: 12),
          phase: .finalAnswer),
      ]
    }
    try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([
      conversation
    ])
    let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }
    let presentation = AgentChatDetailPresentation()
    let session = AgentChatReadingSession()
    let native = AgentChatComposerSession(conversationID: conversation.id)
    func detail(visible: Bool) -> some View {
      AgentChatConversationDetailView(
        controller: controller, isVisible: visible, addSelection: { _ in false }, noteChoices: [],
        prepareNotes: { _ in { _ in } },
        openReference: { _ in false }, openAttachment: { _, _ in }, showChanges: { _ in },
        showConversationChanges: { _ in }, presentation: presentation, readingSession: session,
        nativeSession: native,
        focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil),
        openReply: { _ in }, showList: {},
        newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
        showAccountUsage: {}
      )
      .environment(\.scholiumDocumentSurfaceVisibility, visible ? .active : .retained)
    }
    func readers(_ view: NSView) -> [NSView] {
      if view is WKWebView || view is AgentChatNativeParagraphView { return [view] }
      return view.subviews.flatMap(readers)
    }
    func webReaders(_ view: NSView) -> [WKWebView] {
      (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webReaders)
    }
    let host = NSHostingView(rootView: AnyView(detail(visible: true)))
    let window = mount(host)
    defer {
      presentation.showsTurns = false
      window.contentView = nil
      window.close()
    }
    window.makeKeyAndOrderFront(nil)
    func verify(_ phase: String, _ predicate: () -> Bool) async throws {
      do { try await settle(host, until: predicate) } catch {
        print(
          "CHAT_RETAINED_RESIZE phase=\(phase) readers=\(readers(host).count) initial=\(session.initialTranscriptPhase) request=\(session.viewportRequest != nil) input=\(native.host.editor.isEditable)"
        )
        throw error
      }
    }
    try await verify("initial") {
      session.initialTranscriptPhase == .visible && session.viewportRequest == nil
        && readers(host).count == 4
        && webReaders(host).count == 2 && webReaders(host).allSatisfy { !$0.isLoading }
    }
    let editor = native.host.editor
    editor.setSelectedRange(NSRange(location: 3, length: 6))
    let draftSelection = editor.selectedRange()
    let draftUndo = try #require(editor.undoManager)
    presentation.showsFind = true
    presentation.findFocusRequest = UUID()
    try await verify("find-focus") {
      guard let field = findField(in: host), let fieldEditor = field.currentEditor() else {
        return false
      }
      return window.firstResponder === fieldEditor
    }
    let findEditor = try #require(findField(in: host)?.currentEditor())
    let identities = Set(readers(host).map(ObjectIdentifier.init))
    let anchor = AgentChatReadingSession.Anchor(id: "reply-1", offset: -80)
    let marker = try #require(session.markers[anchor.id]?.view)
    let scroll = try #require(marker.enclosingScrollView)
    let document = try #require(scroll.documentView)
    var requestedBounds = scroll.contentView.bounds
    requestedBounds.origin.y =
      marker.convert(marker.bounds, to: document).minY - anchor.offset - scroll.contentInsets.top
    let constrainedBounds = scroll.contentView.constrainBoundsRect(requestedBounds)
    try #require(constrainedBounds.origin == requestedBounds.origin)
    session.beginUserScroll()
    scroll.contentView.scroll(to: constrainedBounds.origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    session.endUserScroll()
    try #require(session.anchor == anchor)
    func anchorIsPositioned() -> Bool {
      guard let marker = session.markers[anchor.id]?.view, let scroll = marker.enclosingScrollView,
        let document = scroll.documentView
      else {
        return false
      }
      session.viewport?.reconcile()
      let offset =
        marker.convert(marker.bounds, to: document).minY - scroll.contentView.bounds.minY
        - scroll.contentInsets.top
      return abs(offset - anchor.offset) < 2
    }
    try await verify("anchor", anchorIsPositioned)
    // Outline is transient; the native host's hiding must not retain an
    // instruction to reopen it when the same Chat detail becomes visible.
    presentation.showsTurns = true
    host.rootView = AnyView(detail(visible: false))
    try await verify("hidden") {
      readers(host).allSatisfy(\.isHiddenOrHasHiddenAncestor) && native.host.isHidden
    }
    #expect(!presentation.showsTurns, "A hidden Chat must dismiss its Outline presentation.")
    #expect(window.firstResponder !== findEditor)
    window.setContentSize(NSSize(width: 280, height: 640))
    host.layoutSubtreeIfNeeded()
    #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
    host.rootView = AnyView(detail(visible: true))
    try await verify("resumed") {
      guard let fieldEditor = findField(in: host)?.currentEditor() else { return false }
      return readers(host).allSatisfy { !$0.isHiddenOrHasHiddenAncestor } && anchorIsPositioned()
        && window.firstResponder === fieldEditor
    }
    let resumedFindEditor = try #require(findField(in: host)?.currentEditor())
    #expect(
      !presentation.showsTurns, "Returning to Chat must not reopen Outline without another request."
    )
    #expect(presentation.showsFind)
    #expect(window.firstResponder === resumedFindEditor)
    #expect(native.host.editor === editor)
    #expect(editor.string == conversation.draft && controller.selected?.draft == conversation.draft)
    #expect(editor.selectedRange() == draftSelection && editor.undoManager === draftUndo)
    #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
    #expect(session.anchor == anchor && session.viewportRequest == nil)
    #expect(controller.selected?.messages == conversation.messages)
    // Selection can change before the outgoing detail is dismantled. Its
    // transcript must never rebuild readers for the next conversation.
    controller.newConversation()
    let nextID = try #require(controller.selectedID)
    try await verify("outgoing") { !native.host.editor.isEditable }
    #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
    controller.select(conversation.id)
    controller.select(nextID)
    controller.select(conversation.id)
    try await verify("rapid-return") { native.host.editor.isEditable && anchorIsPositioned() }
    #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_LONG_FIXTURE"] == "1"))
  func firstEntryOfLongConversationRecordsNativeViewportStability() async throws {
    _ = NSApplication.shared
    let root = repository.appendingPathComponent(".build/agent-chat-tests/long-entry-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }

    let triptychID = UUID()
    var conversation = AgentChatConversation(triptychID: triptychID)
    conversation.title = "Synthetic long conversation"
    conversation.threadID = "synthetic-long-conversation"
    conversation.messages = (0..<36).flatMap { index in
      let turnID = "synthetic-turn-\(index)"
      var question = AgentChatMessage(
        id: "synthetic-question-\(index)", role: .user,
        text: "请继续核对第 \(index + 1) 组材料中的主张、依据与解释边界。")
      question.turnID = turnID
      var reply = AgentChatMessage(
        id: "synthetic-reply-\(index)", role: .assistant,
        text: "## 第 \(index + 1) 组核对\n\n"
          + String(
            repeating: "这是一段用于测试首次进入聊天时 WebKit 阅读器逐步测量高度的合成回复。它包含中文、English、列表和表格，以便暴露布局稳定性问题。\n\n",
            count: 4)
          + "- 保留来源文本。\n- 单独标出分析。\n\n"
          + "| 项目 | 状态 |\n|---|---|\n| 原文 | 已保留 |\n| 解释 | 待核对 |\n",
        phase: .finalAnswer)
      reply.turnID = turnID
      return [question, reply]
    }
    let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
    try await storage.save([conversation])

    let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await settle { controller.isLoaded }

    let presentation = AgentChatDetailPresentation()
    let session = AgentChatReadingSession()
    let nativeSession = AgentChatComposerSession(conversationID: conversation.id)
    let projection = AgentChatTimelineProjection(conversation.messages)
    let detail = AgentChatConversationDetailView(
      controller: controller, isVisible: true, addSelection: { _ in false },
      noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
      openAttachment: { _, _ in }, showChanges: { _ in },
      showConversationChanges: { _ in }, presentation: presentation, readingSession: session,
      nativeSession: nativeSession,
      focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil),
      openReply: { _ in }, showList: {},
      newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
      showAccountUsage: {})
    let host = NSHostingView(rootView: AnyView(detail))
    let entryStart = ContinuousClock.now
    let window = mount(host)
    defer {
      window.contentView = nil
      window.close()
    }

    let latestID = try #require(projection.ids.last)
    var samples: [CGFloat] = []
    var visibleSamples: [CGFloat] = []
    var firstVisible: Duration?
    let deadline = ContinuousClock.now.advanced(by: .seconds(4))
    while ContinuousClock.now < deadline {
      host.window?.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      if let marker = session.markers[latestID]?.view,
        let scroll = marker.enclosingScrollView, let document = scroll.documentView
      {
        samples.append(scroll.contentView.bounds.minY)
        if session.isInitialTranscriptReady {
          visibleSamples.append(scroll.contentView.bounds.minY)
          if firstVisible == nil { firstVisible = entryStart.duration(to: .now) }
        }
        if samples.count > 1, document.frame.height > scroll.contentView.bounds.height + 300,
          session.viewportRequest == nil,
          abs(scroll.contentView.bounds.maxY - document.frame.height - scroll.contentInsets.bottom)
            < 2
        {
          // Keep sampling after the first valid bottom position so a later
          // reader measurement cannot hide a second jump.
          if samples.count > 80 { break }
        }
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    let scroll = try #require(session.markers[latestID]?.view?.enclosingScrollView)
    let document = try #require(scroll.documentView)
    let jumps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
    let maximumJump = jumps.max() ?? 0
    let visibleJumps = zip(visibleSamples, visibleSamples.dropFirst()).map { abs($1 - $0) }
    let maximumVisibleJump = visibleJumps.max() ?? 0
    let bottomDistance = max(
      0, document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom)
    let changedSamples = samples.enumerated().filter { index, value in
      index == 0 || abs(value - samples[index - 1]) > 1
    }.map { "\($0.offset):\($0.element)" }.joined(separator: ",")
    print(
      "CHAT_LONG_ENTRY messages=\(conversation.messages.count) samples=\(samples.count) "
        + "max_jump=\(maximumJump) visible_samples=\(visibleSamples.count) "
        + "max_visible_jump=\(maximumVisibleJump) bottom_distance=\(bottomDistance) "
        + "first_visible=\(String(describing: firstVisible)) changed=\(changedSamples)"
    )
    #expect(!samples.isEmpty)
    #expect(!visibleSamples.isEmpty)
    #expect(maximumVisibleJump < 2)
    #expect(session.viewportRequest == nil)
    #expect(bottomDistance < 2)
  }

  private final class WeakSidebarReader {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
  }

  private func mount<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    return window
  }

  private func settle(_ host: NSView? = nil, until condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while true {
      host?.window?.layoutIfNeeded()
      host?.layoutSubtreeIfNeeded()
      if condition() { return }
      try #require(
        ContinuousClock.now < deadline,
        "Chat sidebar fixture did not reach its expected native state")
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private func composer(in view: NSView) -> AgentChatComposerHost? {
    (view as? AgentChatComposerHost) ?? view.subviews.lazy.compactMap { composer(in: $0) }.first
  }

  private func findField(in view: NSView) -> NSSearchField? {
    if let field = view as? NSSearchField,
      field.accessibilityIdentifier() == "scholium.chat.find.query"
    {
      return field
    }
    return view.subviews.lazy.compactMap { findField(in: $0) }.first
  }
}
