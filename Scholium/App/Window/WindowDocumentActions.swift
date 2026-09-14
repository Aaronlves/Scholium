import AppKit
import ScholiumContracts

struct WindowNoteRestructureRequest: Identifiable {
    let id = UUID()
    let source: NoteMutationTarget
    let selectionUTF8: Range<Int>?
    let action: DocumentPassageAction?
    let destinations: [NoteMutationTarget]
    var isMerge: Bool { action == nil }
    var createsNote: Bool { action == .extract }
    var title: String { action?.title ?? ScholiumL10n.string("Merge into Another Note…") }
}

extension WindowModel {
    var canMergeCurrentNote: Bool {
        currentDocumentCapabilities.allows(.moveToSystemTrash) && !transferInProgress
            && presentationRouter.sheet == nil
    }

    func presentCurrentDocumentFind() {
        guard let descriptor = currentDocumentDescriptor else { return }
        documentController.session(for: descriptor).findRequested.send()
    }

    func addCurrentNoteToVisibleChat() async {
        guard let note = currentNote, let descriptor = currentDocumentDescriptor else { return }
        do {
            let main = try await workspaceStore.documentLocations.mainWindow(for: self)
            guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey else { throw CancellationError() }
            guard main.addLibraryNoteToChat(note) else { return }
            main.nativeWindowCoordinator?.actions.activateSidebar(.chat)
            main.nativeWindowCoordinator?.makeKeyAndOrderFront()
        } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
    }

    func requestMergeCurrentNote() {
        guard canMergeCurrentNote, let key = currentDocumentDescriptor?.sessionKey else { return }
        Task {
            guard currentDocumentDescriptor?.sessionKey == key else { return }
            await openNoteRestructure(action: nil, captured: nil)
        }
    }

    func performPassageAction(_ action: DocumentPassageAction, captured: MarkdownSourceSelectionSnapshot? = nil) {
        guard let descriptor = currentDocumentDescriptor, presentationRouter.sheet == nil else { return }
        let initialSession = documentController.session(for: descriptor)
        let expectedSelections = initialSession.editorSession.context?.selections
        let expectedGeneration = initialSession.editorSession.generation
        let expectedReadSelection = initialSession.readSelection
        let capturedSourceKind: AgentChatAttachment.Source = captured != nil || presentedDocumentMode == .read ? .savedSource : .editorSnapshot
        Task { @MainActor [weak self] in
            guard let self, self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey else { return }
            do {
                let session = self.documentController.session(for: descriptor)
                let snapshot: MarkdownSourceSelectionSnapshot
                if let captured {
                    guard let note = self.currentNote, !session.hasUnsavedChanges,
                        captured.source.utf8.elementsEqual(note.rawContent.utf8)
                    else { throw AgentChatNoteMaterialError.changedSource }
                    snapshot = captured
                } else if self.presentedDocumentMode == .read {
                    guard let selection = expectedReadSelection, let note = self.currentNote,
                        let selected = MarkdownReviewSourceSelection.review(selection, source: note.rawContent)
                    else { throw AgentChatNoteMaterialError.selectionUnavailable }
                    if let paragraph = try? ParagraphAnchorPlanner.paragraph(in: note.document, atUTF16: selected.sourceRange.utf16LowerBound) {
                        snapshot = MarkdownReviewSourceSelection.passage(selection, source: note.rawContent, paragraphSpan: paragraph) ?? selected
                    } else {
                        snapshot = selected
                    }
                } else {
                    snapshot = try await session.editorSession.passageSourceSnapshot(
                        expectedSelections: expectedSelections, expectedGeneration: expectedGeneration)
                }
                guard self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey else { throw CancellationError() }
                if action == .addToChat {
                    let main = try await self.workspaceStore.documentLocations.mainWindow(for: self)
                    guard self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                        let chat = main.chatController
                    else { throw AgentChatNoteMaterialError.unavailable }
                    let material = AgentChatAttachment(
                        noteID: descriptor.sessionKey.noteID, vaultID: descriptor.reference.vaultID,
                        relativePath: descriptor.reference.relativePath, text: snapshot.excerpt,
                        fingerprint: DocumentFingerprint(content: snapshot.source), sourceLine: snapshot.line,
                        sourceRange: snapshot.sourceRange,
                        source: capturedSourceKind,
                        vaultRole: descriptor.reference.vaultRole)
                    guard chat.attachContext([material]) else { throw AgentChatNoteMaterialError.unavailable }
                    main.nativeWindowCoordinator?.actions.activateSidebar(.chat)
                    main.nativeWindowCoordinator?.makeKeyAndOrderFront()
                } else if action == .relatedMaterial {
                    guard !self.isDetachedDocumentWindow else {
                        throw NoteRestructureError.unavailable(ScholiumL10n.string("Related Material is available in the main window."))
                    }
                    self.showPassageRelatedMaterial(snapshot, descriptor: descriptor)
                } else if action == .copyLink {
                    try await self.copyParagraphLink(snapshot, descriptor: descriptor)
                } else {
                    try await self.preparePassageEditing(snapshot, descriptor: descriptor)
                    await self.openNoteRestructure(action: action, captured: snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                self.reportOperationIssue(error.localizedDescription, kind: .error)
            }
        }
    }

    private func preparePassageEditing(_ snapshot: MarkdownSourceSelectionSnapshot, descriptor: WindowDocumentDescriptor) async throws {
        let session = documentController.session(for: descriptor)
        guard session.conflict == nil, currentDocumentCapabilities.canEditSource else { throw AgentChatNoteMaterialError.changedSource }
        if presentedDocumentMode == .read {
            session.readSelection = .init(
                startLine: snapshot.sourceRange.line, endLine: snapshot.sourceRange.endLine,
                excerpt: snapshot.excerpt, utf16LowerBound: snapshot.sourceRange.utf16LowerBound,
                utf16UpperBound: snapshot.sourceRange.utf16UpperBound)
            requestDocumentMode(.livePreview)
            let deadline = ContinuousClock.now.advanced(by: .seconds(6))
            while presentedDocumentMode == .read || !session.editorSession.isLoaded {
                guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey, ContinuousClock.now < deadline else {
                    throw AgentChatNoteMaterialError.changedSource
                }
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        let current = try await session.editorSession.currentText()
        guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
            current.utf8.elementsEqual(snapshot.source.utf8), !session.editorSession.isComposing
        else { throw AgentChatNoteMaterialError.changedSource }
    }

    private func copyParagraphLink(_ snapshot: MarkdownSourceSelectionSnapshot, descriptor: WindowDocumentDescriptor) async throws {
        guard let target = await currentNoteLinkTarget(), currentDocumentDescriptor?.sessionKey == descriptor.sessionKey else {
            throw NoteRestructureError.unavailable(ScholiumL10n.string("This note has no unambiguous link across the Triptych."))
        }
        let document = NoteDocument(relativePath: descriptor.reference.relativePath, rawContent: snapshot.source)
        let paragraph = try ParagraphAnchorPlanner.paragraph(in: document, atUTF16: snapshot.sourceRange.utf16LowerBound)
        if snapshot.sourceRange.utf16UpperBound > paragraph.utf16UpperBound {
            let tail = (snapshot.source as NSString).substring(
                with: .init(
                    location: paragraph.utf16UpperBound,
                    length: snapshot.sourceRange.utf16UpperBound - paragraph.utf16UpperBound))
            guard tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ParagraphAnchorError.unsupportedParagraph }
        }
        let plan = try ParagraphAnchorPlanner.ensureAnchor(in: document, atUTF16: snapshot.sourceRange.utf16LowerBound)
        let session = documentController.session(for: descriptor)
        let editor = session.editorSession
        let readsEditor = !plan.edits.isEmpty || presentedDocumentMode != .read
        if let edit = plan.edits.first {
            try await preparePassageEditing(snapshot, descriptor: descriptor)
            guard plan.edits.count == 1, let webView = editor.webView else { throw AgentChatNoteMaterialError.unavailable }
            let bytes = Array(snapshot.source.utf8)
            let from = String(decoding: bytes[..<edit.startUTF8], as: UTF8.self).utf16.count
            let to = String(decoding: bytes[..<edit.endUTF8], as: UTF8.self).utf16.count
            _ = try await editor.send(
                .replacePassage(
                    expectedText: snapshot.source, fromUTF16: from,
                    toUTF16: to, replacement: edit.replacement, preserveSelection: true), in: webView)
        }
        guard let capabilities = windowWorkspaceController.activeCapabilities else { throw AgentChatNoteMaterialError.unavailable }
        if readsEditor {
            try await documentController.flushForExternalOperation(session: session, target: .workspace(descriptor.sessionKey))
        }
        let saved = try await capabilities.documents.load(.init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath))
        let current = readsEditor ? try await editor.currentText() : snapshot.source
        guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
            current.utf8.elementsEqual(saved.rawContent.utf8),
            ParagraphAnchorPlanner.anchors(in: saved).filter({ $0.id == plan.anchorID }).count == 1
        else { throw AgentChatNoteMaterialError.changedSource }
        try copyTextToClipboard("[[\(target)#^\(plan.anchorID)]]")
    }

    private func showPassageRelatedMaterial(_ snapshot: MarkdownSourceSelectionSnapshot, descriptor: WindowDocumentDescriptor) {
        guard let capabilities = windowWorkspaceController.activeCapabilities else { return }
        researchController.selectInspectorMode(.related)
        nativeWindowCoordinator?.actions.setResearchInspectorVisible(true)
        let seed = RelatedContentSeedSnapshot(
            noteID: .init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath),
            source: snapshot.source, focuses: [.init(kind: .selectedPassage, text: snapshot.excerpt)])
        researchController.relatedMaterials.find(
            capture: {
                RelatedMaterialsSeed(
                    request: .init(seed: seed),
                    attachment: .init(
                        noteID: descriptor.sessionKey.noteID, vaultID: descriptor.reference.vaultID,
                        relativePath: descriptor.reference.relativePath, text: snapshot.excerpt, fingerprint: seed.fingerprint,
                        sourceLine: snapshot.line, sourceRange: snapshot.sourceRange, vaultRole: descriptor.reference.vaultRole),
                    insertionPoint: nil, usesParagraph: false)
            }, retrieve: { try await capabilities.discovery.relatedContent($0) },
            references: workspaceCatalog?.notes.map(\.reference) ?? [], automatic: false,
            canPublish: { [weak self] in self?.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey },
            linkTarget: { _ in nil })
    }

    private func openNoteRestructure(action: DocumentPassageAction?, captured: MarkdownSourceSelectionSnapshot?) async {
        guard let descriptor = currentDocumentDescriptor, let capabilities = windowWorkspaceController.activeCapabilities else { return }
        do {
            let sourceText: String
            if let captured {
                sourceText = captured.source
            } else if presentedDocumentMode != .read {
                sourceText = try await documentController.session(for: descriptor).editorSession.currentText()
            } else if let note = currentNote {
                sourceText = note.rawContent
            } else {
                throw AgentChatNoteMaterialError.unavailable
            }
            try await workspaceStore.flushEditors(in: capabilities.runtimeIdentity.triptychID)
            let vaults = try await capabilities.documents.snapshot()
            guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey, presentationRouter.sheet == nil,
                let vault = vaults.first(where: { $0.vault.id == descriptor.reference.vaultID }),
                let source = vault.documents.first(where: { $0.stableIdentity.resolvedID == descriptor.sessionKey.noteID }),
                source.document.rawContent.utf8.elementsEqual(sourceText.utf8)
            else { throw AgentChatNoteMaterialError.changedSource }
            let range: Range<Int>?
            if let captured,
                let nativeRange = Range(
                    NSRange(
                        location: captured.sourceRange.utf16LowerBound,
                        length: captured.sourceRange.utf16UpperBound - captured.sourceRange.utf16LowerBound), in: sourceText)
            {
                range = sourceText[..<nativeRange.lowerBound].utf8.count..<sourceText[..<nativeRange.upperBound].utf8.count
            } else {
                range = nil
            }
            let sourceTarget = NoteMutationTarget(documentID: source.id, stableNoteID: descriptor.sessionKey.noteID, revision: source.fingerprint)
            let targets = vault.documents.compactMap { note -> NoteMutationTarget? in
                guard note.id != source.id, let id = note.stableIdentity.resolvedID, note.capabilities.canEditSource else { return nil }
                return .init(documentID: note.id, stableNoteID: id, revision: note.fingerprint)
            }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            presentationRouter.present(.noteRestructure(.init(source: sourceTarget, selectionUTF8: range, action: action, destinations: targets)))
        } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
    }

    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws -> NoteRestructurePreview {
        guard let capabilities = windowWorkspaceController.activeCapabilities else { throw AgentChatNoteMaterialError.unavailable }
        try await workspaceStore.flushEditors(in: capabilities.runtimeIdentity.triptychID)
        if case .existing(let selected) = request.destination {
            let vaults = try await capabilities.documents.snapshot()
            guard
                let current = vaults.first(where: { $0.vault.id == selected.documentID.vaultID })?.documents.first(where: {
                    $0.id == selected.documentID && $0.stableIdentity.resolvedID == selected.stableNoteID && $0.capabilities.canEditSource
                })
            else { throw AgentChatNoteMaterialError.changedSource }
            guard current.fingerprint == selected.revision else { throw AgentChatNoteMaterialError.changedSource }
        }
        return try await capabilities.documents.prepareNoteRestructure(request)
    }

    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws {
        guard let capabilities = windowWorkspaceController.activeCapabilities else { throw AgentChatNoteMaterialError.unavailable }
        try await workspaceStore.flushEditors(in: capabilities.runtimeIdentity.triptychID)
        do {
            let outcome = try await capabilities.documents.commitNoteRestructure(preview)
            _ = await refreshAfterResearchHandoff()
            if outcome.derivedRefreshWarning != nil || outcome.identityRecoveryWarning != nil {
                reportOperationIssue(
                    ScholiumL10n.string("Notes reorganized; some views could not refresh. Use Refresh instead of repeating the operation."), kind: .information)
                return
            }
            if let reference = workspaceCatalog?.notes.first(where: {
                $0.reference.vaultID == outcome.committedValue.destination.vaultID
                    && $0.reference.relativePath == outcome.committedValue.destination.relativePath
            })?.reference {
                await openWorkspaceReference(reference)
            }
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        reportOperationIssue(ScholiumL10n.string("Notes reorganized."), kind: .information)
    }
}
