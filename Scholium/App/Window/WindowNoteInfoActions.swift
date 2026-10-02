import AppKit
import ScholiumContracts

extension WindowModel {
    /// Note Info's synchronous action keeps its panel open until both the pane
    /// and attachment picker are admitted. A busy transition remains retryable.
    func requestNoteInfoPDFAttachment() throws {
        guard acceptsNoteInfoInteraction, PDFReaderWindowCommand.isAvailable(in: self),
            !sidePaneCoordinator.isTransitioning, pdfReaderController.annotationDraft == nil, pdfReaderController.canAttach
        else { throw NoteInfoActionError.readerUnavailable }
        sidePaneCoordinator.setPDFVisible(true)
        guard PDFReaderWindowCommand.isVisible(in: self), pdfReaderController.canAttach else {
            throw NoteInfoActionError.readerUnavailable
        }
        pdfReaderController.requestAttachPDF()
        guard pdfReaderController.attachRequested else { throw NoteInfoActionError.readerUnavailable }
    }

    private var acceptsNoteInfoInteraction: Bool {
        !transferInProgress && !windowCloseCoordinator.isPreparingOrFinalized
            && nativeWindowCoordinator?.isNativeCloseInProgress != true
            && nativeWindowCoordinator?.registry.isTerminationAttemptInProgress != true
    }

    func showNoteInfo() {
        guard acceptsNoteInfoInteraction else { return }
        if let controller = noteInfoWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let captured = currentDocumentDescriptor?.sessionKey
        let origin = NSApp.keyWindow
        Task { @MainActor [weak self] in
            guard let self, captured == self.currentDocumentDescriptor?.sessionKey else { return }
            do {
                let context = try await self.currentNoteInfoContext()
                guard self.noteInfoWindowController == nil, self.acceptsNoteInfoInteraction
                else { return }
                let controller = NoteInfoWindowController(
                    context: context,
                    reload: { [weak self] target in
                        guard let self else { throw CancellationError() }
                        return try await self.currentNoteInfoContext(expected: target)
                    },
                    apply: { [weak self] context, edits in
                        guard let self else { throw CancellationError() }
                        return try await self.applyNoteInfoPanelChanges(context, edits: edits)
                    },
                    attachPDF: { [weak self] target in
                        guard let self else { throw CancellationError() }
                        try self.validateNoteInfoTarget(target)
                        try self.requestNoteInfoPDFAttachment()
                        self.noteInfoWindowController?.close()
                        origin?.makeKeyAndOrderFront(nil)
                    },
                    openSource: { [weak self] target in
                        guard let self else { throw CancellationError() }
                        try self.validateNoteInfoTarget(target)
                        self.requestDocumentMode(.source)
                    })
                controller.onClose = { [weak self, weak controller] in
                    guard self?.noteInfoWindowController === controller else { return }
                    self?.noteInfoWindowController = nil
                }
                self.noteInfoWindowController = controller
                controller.present(relativeTo: origin)
            } catch is CancellationError { return } catch {
                self.reportOperationIssue(error.localizedDescription, kind: .error)
            }
        }
    }

    func currentNoteInfoContext(expected: SourceAttachmentTarget? = nil) async throws -> NoteInfoContext {
        guard let descriptor = currentDocumentDescriptor,
            let note = currentNote?.hydratedSnapshot,
            let vault = registeredVaults.first(where: { $0.id == descriptor.reference.vaultID })
        else { throw NoteInfoActionError.changed }
        let target = SourceAttachmentTarget(
            noteID: descriptor.sessionKey.noteID, vaultID: descriptor.reference.vaultID,
            relativePath: descriptor.reference.relativePath)
        if let expected { guard target == expected else { throw NoteInfoActionError.changed } }
        let session = documentController.session(for: descriptor)
        let source: String
        if session.isEditing || session.editorSession.hasRecoverableBuffer {
            guard !session.editorSession.isComposing else { throw NoteInfoActionError.composing }
            let captured = try await session.editorSession.currentTextSnapshot()
            guard captured.generation == session.editorSession.generation,
                documentController.retainedSession(for: descriptor.sessionKey) === session
            else { throw NoteInfoActionError.changed }
            source = captured.text
        } else {
            source = note.document.rawContent
        }
        try validateNoteInfoTarget(target)
        return NoteInfoContext(
            target: target, title: note.summary.title,
            document: NoteDocument(relativePath: target.relativePath, rawContent: source),
            fileURL: URL(fileURLWithPath: vault.canonicalPath, isDirectory: true).appendingPathComponent(target.relativePath),
            canEdit: currentDocumentCapabilities.canEditSource && session.conflict == nil && !transferInProgress,
            fileMetadata: note.fileMetadata)
    }

    func setNotePDFBinding(_ path: String?, for captured: SourceAttachmentTarget, expectedBinding: String?) async throws {
        let context = try await currentNoteInfoContext(expected: captured)
        guard try PDFNoteBinding.path(in: context.document) == expectedBinding else { throw NoteInfoActionError.changed }
        guard path != expectedBinding else { return }
        _ = try await applyNoteInfo(context, edits: ["pdf": path.map(FrontmatterEditValue.string) ?? .remove])
    }

    private func validateNoteInfoTarget(_ target: SourceAttachmentTarget) throws {
        guard let descriptor = currentDocumentDescriptor,
            descriptor.sessionKey.noteID == target.noteID,
            descriptor.reference.vaultID == target.vaultID,
            descriptor.reference.relativePath == target.relativePath,
            acceptsNoteInfoInteraction
        else { throw NoteInfoActionError.changed }
    }

    func applyNoteInfoPanelChanges(_ context: NoteInfoContext, edits: [String: FrontmatterEditValue]) async throws -> NoteInfoContext {
        try validateNoteInfoTarget(context.target)
        guard edits["pdf"] != nil else { return try await applyNoteInfo(context, edits: edits) }
        // A researcher-driven binding change cannot leave an unfinished draft
        // or failed PDF save behind. Freeze reader input through the source commit.
        let departure = pdfReaderController.beginDeparture()
        defer { pdfReaderController.endDeparture(departure) }
        try await pdfReaderController.flushAnnotations()
        return try await applyNoteInfo(context, edits: edits)
    }

    private func applyNoteInfo(_ context: NoteInfoContext, edits: [String: FrontmatterEditValue]) async throws -> NoteInfoContext {
        try validateNoteInfoTarget(context.target)
        guard context.canEdit, currentDocumentCapabilities.canEditSource,
            let descriptor = currentDocumentDescriptor
        else { throw NoteInfoActionError.readOnly }
        let session = documentController.session(for: descriptor)
        guard session.conflict == nil, !session.editorSession.isComposing else {
            throw session.editorSession.isComposing ? NoteInfoActionError.composing : .changed
        }
        let patch = try NoteInfoMetadataPlanner.plan(document: context.document, edits: edits)
        guard let patch else { return try await currentNoteInfoContext(expected: context.target) }
        if presentedDocumentMode == .read {
            requestDocumentMode(.livePreview)
            let deadline = ContinuousClock.now.advanced(by: .seconds(6))
            while presentedDocumentMode == .read || !session.editorSession.isLoaded {
                try validateNoteInfoTarget(context.target)
                guard ContinuousClock.now < deadline else { throw NoteInfoActionError.changed }
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        try validateNoteInfoTarget(context.target)
        let source = try await session.editorSession.currentText()
        try Task.checkCancellation()
        try validateNoteInfoTarget(context.target)
        guard session.conflict == nil, !session.editorSession.isComposing else { throw NoteInfoActionError.changed }
        if source.utf8.elementsEqual(patch.expectedSource.utf8) {
            try await session.editorSession.applySourcePatch(patch)
        } else if !source.utf8.elementsEqual(patch.resultingSource.utf8) {
            throw NoteInfoActionError.changed
        }
        // A failed save leaves the editor's exact candidate intact. Retrying
        // Apply acknowledges that same candidate rather than inserting twice.
        try await documentController.flushForExternalOperation(session: session, target: .workspace(descriptor.sessionKey))
        try validateNoteInfoTarget(context.target)
        if edits["pdf"] != nil { refreshPDFReaderContext() }
        return try await currentNoteInfoContext(expected: context.target)
    }
}

private enum NoteInfoActionError: LocalizedError {
    case changed, composing, readOnly, readerUnavailable
    var errorDescription: String? {
        switch self {
        case .changed: ScholiumL10n.string("The note changed. Return to this note and reload Note Info before applying changes.")
        case .composing: ScholiumL10n.string("Finish composition before changing note information.")
        case .readOnly: ScholiumL10n.string("This note is read-only in Scholium.")
        case .readerUnavailable: ScholiumL10n.string("The PDF reader is busy or unavailable. Finish the current PDF task or leave Full Screen, then try again.")
        }
    }
}
