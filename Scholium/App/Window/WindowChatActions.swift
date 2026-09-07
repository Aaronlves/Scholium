import Foundation
import ScholiumContracts

extension WindowModel {
  @MainActor
  func addCurrentSelectionToChat() async {
    guard let chat = chatController, let note = currentNote,
      let descriptor = currentDocumentDescriptor,
      let noteID = note.workspaceSnapshot?.stableIdentity.resolvedID
    else { return }
    let session = documentController.session(for: descriptor).editorSession
    do {
      let snapshot = try await session.chatSelection()
      guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
        chatController === chat
      else { return }
      chat.attach(
        .init(
          noteID: noteID, vaultID: descriptor.reference.vaultID,
          relativePath: note.relativePath, text: snapshot.excerpt,
          fingerprint: NoteDocument(relativePath: note.relativePath, rawContent: snapshot.source)
            .fingerprint,
          sourceLine: snapshot.line))
    } catch {
      reportOperationIssue(
        String(localized: "Select a passage in Edit or Source before adding it to Chat."),
        kind: .information)
    }
  }

  @MainActor @discardableResult
  func openChatReference(_ url: URL) -> Bool {
    guard let reference = AgentChatReference.parse(url) else { return false }
    let matches =
      workspaceCatalog?.notes.filter {
        $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == reference.noteID
      } ?? []
    guard matches.count == 1, let note = matches.first else {
      reportOperationIssue(
        String(localized: "This note cannot be located in the current Triptych."),
        kind: .information)
      return false
    }
    researchController.requestOpen(note.reference, sourceLine: reference.line)
    return true
  }
}
