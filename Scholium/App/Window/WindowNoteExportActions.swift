import AppKit
import ScholiumContracts

extension WindowModel {
    func requestCurrentNoteExport() {
        guard canPerformNoteAction(.export),
            let descriptor = currentDocumentDescriptor,
            let note = currentNote?.hydratedSnapshot
        else { return }

        noteExportPreparationInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.noteExportPreparationInProgress = false }
            do {
                let session = self.documentController.session(for: descriptor)
                let source: String
                if session.hasUnsavedChanges || session.retainsEditorSurface {
                    guard !session.editorSession.isComposing else {
                        throw NoteExportActionError.composing
                    }
                    let snapshot = try await session.editorSession.currentTextSnapshot()
                    guard self.documentController.retainedSession(for: descriptor.sessionKey) === session,
                        snapshot.generation == session.editorSession.generation,
                        !session.editorSession.isComposing
                    else { throw NoteExportActionError.changedDuringPreparation }
                    source = snapshot.text
                } else {
                    source = note.document.rawContent
                }
                guard self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey else {
                    throw NoteExportActionError.changedDuringPreparation
                }
                let document = NoteDocument(relativePath: note.id.relativePath, rawContent: source)
                guard let capabilities = self.windowWorkspaceController.activeCapabilities else {
                    throw NoteExportActionError.changedDuringPreparation
                }
                let embeddedImages = try await capabilities.documents.exportImages(
                    for: VaultQualifiedNoteID(
                        vaultID: descriptor.reference.vaultID,
                        relativePath: descriptor.reference.relativePath
                    ),
                    markdownSource: source
                )
                guard self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey else {
                    throw NoteExportActionError.changedDuringPreparation
                }
                var excludedRoots = self.registeredVaults.map {
                    URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
                }
                if let works = self.workspaceAssignment?.vault(for: .output) {
                    excludedRoots.append(
                        URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
                            .deletingLastPathComponent()
                            .appendingPathComponent(".scholium", isDirectory: true)
                    )
                }
                let controller = ScholiumNoteExportWindowController(
                    document: document, title: note.summary.title,
                    embeddedImages: embeddedImages,
                    excludedRoots: excludedRoots,
                    appearance: workspaceStore.cssSnippetStore.selectedAppearanceProfile?.settings
                        ?? .defaultSettings,
                    colorScheme: shellState.colorScheme
                )
                controller.onClose = { [weak self, weak controller] in
                    guard let self, self.noteExportWindowController === controller else { return }
                    self.noteExportWindowController = nil
                }
                self.noteExportWindowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
            } catch is CancellationError {
                return
            } catch {
                self.reportOperationIssue(error.localizedDescription, kind: .error)
            }
        }
    }
}

private enum NoteExportActionError: LocalizedError {
    case composing
    case changedDuringPreparation

    var errorDescription: String? {
        switch self {
        case .composing:
            ScholiumL10n.string("Finish the current text composition before exporting this note.")
        case .changedDuringPreparation:
            ScholiumL10n.string("The note changed while export was being prepared. Try Export Note again.")
        }
    }
}
