import Foundation
import ScholiumContracts

extension WindowModel {
  @MainActor
  func openSystemNotification(_ route: SystemNotificationRoute) async -> SidebarContent? {
    switch route {
    case .agentChange(let change):
      await openNotifiedAgentChange(change)
      return nil
    case .chat(let destination):
      guard workspaceAssignment?.id == destination.triptychID, let chat = chatController else { return nil }
      let opened = await chat.selectNotification(destination)
      guard chatController === chat, workspaceAssignment?.id == destination.triptychID else { return nil }
      if opened {
        return .chat
      } else {
        reportOperationIssue(ScholiumL10n.string("This conversation is no longer available."), kind: .information)
        return nil
      }
    }
  }

  @MainActor @discardableResult
  func addCurrentSelectionToChat(inquiry: AgentChatSelectionInquiry = .ask) async -> Bool {
    guard let chat = chatController, let note = currentNote,
      let descriptor = currentDocumentDescriptor,
      let noteID = note.workspaceSnapshot?.stableIdentity.resolvedID
    else { return false }
    let session = documentController.session(for: descriptor)
    let selectedConversation = chat.selectedID
    let mode = presentedDocumentMode
    do {
      let snapshot: MarkdownSourceSelectionSnapshot
      if mode == .read {
        guard !session.hasUnsavedChanges,
          session.renderedReadFingerprint == note.document.fingerprint.sha256,
          let selection = session.readSelection,
          let captured = MarkdownReviewSourceSelection.review(selection, source: note.rawContent)
        else { throw AgentChatNoteMaterialError.selectionUnavailable }
        snapshot = captured
      } else {
        snapshot = try await session.editorSession.selectedSourceSnapshot()
      }
      guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
        chatController === chat, chat.selectedID == selectedConversation, presentedDocumentMode == mode
      else { return false }
      if chat.selected == nil || chat.selected?.archivedAt != nil { chat.newConversation() }
      guard let conversationID = chat.selectedID else { return false }
      return chat.prepareSelectionInquiry([
        .init(noteID: noteID, vaultID: descriptor.reference.vaultID,
          relativePath: note.relativePath, text: snapshot.excerpt,
          fingerprint: DocumentFingerprint(content: snapshot.source),
          sourceLine: snapshot.line, sourceRange: snapshot.sourceRange,
          source: mode == .read ? .savedSource : .editorSnapshot,
          vaultRole: descriptor.reference.vaultRole)], inquiry: inquiry, to: conversationID)
    } catch {
      reportOperationIssue(String(localized: "Select an exact passage in Edit or Source if the reading selection cannot be located."),
        kind: .information)
      return false
    }
  }

  @MainActor
  func canAddLibraryNoteToChat(_ note: WindowDocumentLocation) -> Bool {
    guard let target = NoteMutationTarget(note) else { return false }
    return canAddNotesToChat([SidebarNoteDragItem(target)])
  }

  @MainActor @discardableResult
  func addLibraryNoteToChat(_ note: WindowDocumentLocation) -> Bool {
    guard let target = NoteMutationTarget(note), addNotesToChat([SidebarNoteDragItem(target)]) else {
      reportOperationIssue(AgentChatNoteMaterialError.unavailable.localizedDescription, kind: .information)
      return false
    }
    return true
  }

  @MainActor
  func canAddNotesToChat(_ items: [SidebarNoteDragItem]) -> Bool {
    guard !items.isEmpty, let chat = chatController, chat.isLoaded,
      workspaceAssignment?.id == chat.triptychID,
      windowWorkspaceController.activeCapabilities != nil,
      let notes = workspaceCatalog?.notes,
      chat.selectedID.map({ !chat.preparingMaterials.contains($0) }) ?? true else { return false }
    return items.allSatisfy { (try? AgentChatPasteboardSnapshot.resolve($0, in: notes)) != nil }
  }

  @MainActor @discardableResult
  func addNotesToChat(_ items: [SidebarNoteDragItem]) -> Bool {
    guard canAddNotesToChat(items), let chat = chatController,
      let runtime = windowWorkspaceController.activeCapabilities?.runtimeIdentity else { return false }
    if chat.selected == nil || chat.selected?.archivedAt != nil { chat.newConversation() }
    guard let conversationID = chat.selectedID else { return false }
    chat.presentContext(in: conversationID)
    Task { @MainActor [weak self, weak chat] in
      guard let self, let chat, self.chatController === chat,
        self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime else { return }
      await chat.addTransferredMaterials(items.map(AgentChatTransferredMaterial.note), origin: .drop,
        to: conversationID) { [weak self] item in
          guard let self, self.chatController === chat,
            self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime else { throw CancellationError() }
          let note = try AgentChatPasteboardSnapshot.resolve(item, in: self.workspaceCatalog?.notes ?? [])
          try await self.addNoteToChat(note, conversationID: conversationID)
        }
    }
    return true
  }

  @MainActor
  func addNoteToChat(_ note: WorkspaceCatalogNote, conversationID: UUID) async throws {
    guard let chat = chatController,
      chat.conversations.contains(where: { $0.id == conversationID && $0.archivedAt == nil }),
      let capabilities = windowWorkspaceController.activeCapabilities,
      let noteID = note.reference.stableNoteID.flatMap(UUID.init(uuidString:)),
      workspaceCatalog?.notes.contains(where: { $0.reference == note.reference }) == true
    else { throw AgentChatNoteMaterialError.unavailable }
    let reference = note.reference
    let key = DocumentSessionKey(vaultID: reference.vaultID, noteID: noteID)
    let document = try await capabilities.documents.load(.init(vaultID: reference.vaultID, relativePath: reference.relativePath))
    try Task.checkCancellation()
    guard chatController === chat,
      windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
      workspaceCatalog?.notes.contains(where: { $0.reference == reference && $0.fingerprint == document.fingerprint }) == true
    else { throw AgentChatNoteMaterialError.changedSource }
    let retained = documentController.retainedSession(for: key)
    let text: String
    let source: AgentChatAttachment.Source
    if let retained, retained.hasUnsavedChanges || retained.retainsEditorSurface {
      guard !retained.editorSession.isComposing else { throw AgentChatNoteMaterialError.composing }
      do { text = try await retained.editorSession.currentTextSnapshot().text }
      catch is CancellationError { throw CancellationError() }
      catch { throw AgentChatNoteMaterialError.editorUnavailable }
      guard documentController.retainedSession(for: key) === retained,
        !retained.editorSession.isComposing else { throw AgentChatNoteMaterialError.editorUnavailable }
      source = .editorSnapshot
    } else {
      text = document.rawContent; source = .savedSource
    }
    try Task.checkCancellation()
    guard chatController === chat,
      windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
      workspaceCatalog?.notes.contains(where: { $0.reference == reference }) == true
    else { throw AgentChatNoteMaterialError.changedSource }
    guard chat.attachContext([.init(noteID: noteID, vaultID: reference.vaultID,
      relativePath: reference.relativePath, text: text, fingerprint: DocumentFingerprint(content: text),
      sourceLine: 1, extent: .wholeNote, source: source, vaultRole: reference.vaultRole)], to: conversationID)
    else { throw AgentChatNoteMaterialError.unavailable }
  }

  @MainActor
  func openChatAttachment(_ attachment: AgentChatAttachment) async {
    _ = openChatSource(noteID: attachment.noteID, vaultID: attachment.vaultID,
      line: attachment.sourceLine, revision: attachment.fingerprint.sha256, sourceRange: attachment.sourceRange, excerpt: attachment.text)
  }

  @MainActor @discardableResult
  func openChatReference(_ url: URL) -> Bool {
    guard let reference = AgentChatReference.parse(url) else { return false }
    return openChatSource(noteID: reference.noteID, vaultID: reference.vaultID,
      line: reference.line, revision: reference.revision)
  }

  @MainActor private func openChatSource(noteID: UUID, vaultID: UUID?, line: Int?, revision: String?, sourceRange: SearchSourceRange? = nil, excerpt: String? = nil) -> Bool {
    let matches = workspaceCatalog?.notes.filter {
      $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == noteID
        && (vaultID == nil || $0.reference.vaultID == vaultID)
    } ?? []
    guard matches.count == 1, let reference = matches.first?.reference,
      let runtime = windowWorkspaceController.activeCapabilities?.runtimeIdentity else {
      reportOperationIssue(String(localized: "This note cannot be located in the current Triptych."), kind: .information)
      return false
    }
    let target = DocumentSessionKey(vaultID: reference.vaultID, noteID: noteID)
    let navigationMode = presentedDocumentMode
    enqueueDocumentTransition(preservingCurrentEditorState: false, retainingCurrentDocument: target) { [weak self] in
      guard let self, self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime else {
        throw CancellationError()
      }
      let alreadyCurrent = self.currentDocumentDescriptor?.sessionKey == target
      if !alreadyCurrent {
        try await self.activateWorkspaceReference(reference, tabActivation: .place(.newTab))
      }
      let canEdit = self.currentNote?.workspaceSnapshot?.capabilities.canEditSource == true
      let status = try await self.chatSourceLocationStatus(reference: reference, target: target,
        line: line, revision: revision, mode: canEdit ? navigationMode : .read, sourceRange: sourceRange, excerpt: excerpt)
      try Task.checkCancellation()
      guard self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime,
        self.currentDocumentDescriptor?.sessionKey == target else { throw CancellationError() }
      self.documentController.requestSourceLocation(line: status == .current ? line : nil,
        range: status == .current ? sourceRange : nil, requiresExactSelection: sourceRange != nil,
        sourceFingerprint: status == .current ? revision : nil)
      if !alreadyCurrent { self.requestPresentationMode = canEdit ? navigationMode : nil }
      switch status {
      case .current, .identity: break
      case .changed:
        self.reportOperationIssue(String(localized: "This reference is from a different version. The Note was opened without selecting a passage.", bundle: .module), kind: .information)
      case .unverified:
        self.reportOperationIssue(String(localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module), kind: .information)
      }
    }
    return true
  }

  @MainActor private func chatSourceLocationStatus(reference: VaultNoteReference, target: DocumentSessionKey,
    line: Int?, revision: String?, mode: NotePresentationMode, sourceRange: SearchSourceRange?, excerpt: String?) async throws -> ChatSourceLocationStatus {
    guard let revision else { return line == nil ? .identity : .unverified }
    let session = documentController.session(for: target)
    guard !session.editorSession.isComposing else { return .unverified }
    let text: String
    if mode != .read, session.retainsEditorSurface, session.editorSession.isReady, session.editorSession.isLoaded {
      do {
        let snapshot = try await session.editorSession.currentTextSnapshot()
        guard documentController.retainedSession(for: target) === session,
          snapshot.generation == session.editorSession.generation, !session.editorSession.isComposing else { return .unverified }
        text = snapshot.text
      } catch is CancellationError { throw CancellationError() }
      catch { return .unverified }
    } else {
      guard !session.hasUnsavedChanges else { return .unverified }
      do {
        let document = try await documentController.load(.init(vaultID: reference.vaultID, relativePath: reference.relativePath))
        guard !session.hasUnsavedChanges, !session.editorSession.isComposing else { return .unverified }
        if document.fingerprint.sha256 != revision { return .changed }
        guard currentNote?.workspaceSnapshot?.fingerprint == document.fingerprint else { return .unverified }
        text = document.rawContent
      } catch is CancellationError { throw CancellationError() }
      catch { return .unverified }
    }
    guard DocumentFingerprint(content: text).sha256 == revision else { return .changed }
    if let sourceRange {
      let lower = sourceRange.utf16LowerBound, upper = sourceRange.utf16UpperBound
      guard lower >= 0, upper > lower, upper <= text.utf16.count,
        let range = Range(NSRange(location: lower, length: upper - lower), in: text),
        let excerpt, text[range].utf8.elementsEqual(excerpt.utf8) else { return .unverified }
    }
    let lineCount = text.reduce(1) { count, character in
      count + (character == "\n" || character == "\r\n" || character == "\r" ? 1 : 0)
    }
    if let line, line < 1 || line > lineCount { return .unverified }
    return .current
  }

}

enum AgentChatNoteMaterialError: LocalizedError {
  case unavailable, changedSource, editorUnavailable, composing, selectionUnavailable
  var errorDescription: String? {
    switch self {
    case .unavailable: String(localized: "The Note or conversation is no longer available.")
    case .changedSource: String(localized: "The Note changed while it was being read. Choose it again after the Library refreshes.")
    case .editorUnavailable: String(localized: "The current editor snapshot is unavailable. Keep the Note open and try again.")
    case .selectionUnavailable: String(localized: "Select an exact passage in Edit or Source if the reading selection cannot be located.")
    case .composing: String(localized: "Finish editing with the input method, then try adding the Note again.")
    }
  }
}

private enum ChatSourceLocationStatus { case identity, current, changed, unverified }
