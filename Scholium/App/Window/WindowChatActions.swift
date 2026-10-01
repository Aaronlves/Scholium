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
        do {
            return try await stageCurrentSelectionInChat(inquiry: inquiry)
        } catch is CancellationError {
            return false
        } catch {
            reportOperationIssue(error.localizedDescription, kind: .information)
            return false
        }
    }

    /// Menu, composer and Ask Agent share one captured destination and preparation
    /// scope. Their invoking surfaces retain ownership of error presentation.
    @MainActor
    private func stageCurrentSelectionInChat(
        inquiry: AgentChatSelectionInquiry, newConversation: Bool = false, validate: @escaping AgentSelectionValidation = { true }
    ) async throws -> Bool {
        guard !Task.isCancelled, let chat = chatController else { return false }
        let selected = chat.selectedID
        @MainActor func capture() async throws {
            let attachment = try await currentSelectionAttachment()
            guard await validate(), !Task.isCancelled, chatController === chat, selected == chat.selectedID else {
                throw CancellationError()
            }
            // A missing or archived destination has no live draft to guard.
            // Create its replacement only after a valid passage is captured.
            if newConversation || chat.selected == nil || chat.selected?.isAvailable == false { chat.newConversation() }
            guard let conversationID = chat.selectedID,
                chat.prepareSelectionInquiry([attachment], inquiry: inquiry, to: conversationID)
            else { throw AgentChatNoteMaterialError.unavailable }
        }
        if !newConversation, let selected, chat.selected?.isAvailable == true {
            var failure: (any Error)?
            let prepared = await chat.performMaterialPreparation(in: selected) {
                do { try await capture() } catch {
                    failure = error
                    throw CancellationError()
                }
            }
            if let failure { throw failure }
            return prepared
        }
        try await capture()
        return true
    }

    @MainActor
    func runSelectionInquiry(_ inquiry: AgentChatSelectionInquiry, validate: @escaping AgentSelectionValidation, continueInChat: @escaping () -> Void)
        async throws
        -> AgentSelectionResult?
    {
        guard !Task.isCancelled else { return nil }
        guard let chat = chatController, let descriptor = currentDocumentDescriptor else { throw AgentChatNoteMaterialError.unavailable }
        do {
            if inquiry.operation == nil {
                let visible =
                    shellState.libraryVisible && shellState.sidebarContent == .chat
                    && chat.transcriptReaders[nativeWindowID] != nil
                    && chat.transcriptReaders[nativeWindowID] == chat.selectedID
                let prepared = try await stageCurrentSelectionInChat(inquiry: inquiry, newConversation: !visible) { [self] in
                    guard await validate() else { return false }
                    return currentDocumentDescriptor?.sessionKey == descriptor.sessionKey
                }
                if prepared { continueInChat() }
                return nil
            }
            let attachment = try await currentSelectionAttachment()
            guard chatController === chat, currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                await validate(), !Task.isCancelled
            else { return nil }
            let model = WritingAssistancePreferences.shared.model
            if let retained = selectionResult, retained.inquiry == inquiry, retained.model == model,
                retained.attachment.noteID == attachment.noteID, retained.attachment.vaultID == attachment.vaultID,
                retained.attachment.fingerprint == attachment.fingerprint, retained.attachment.sourceRange == attachment.sourceRange,
                retained.attachment.text == attachment.text,
                (retained.result.adopt != nil) == (inquiry.operation == .polish && presentedDocumentMode != .read),
                !retained.result.isAdopted
            {
                return retained.result
            }
            await selectionResult?.result.stopAndWait()
            guard !Task.isCancelled, chatController === chat,
                currentDocumentDescriptor?.sessionKey == descriptor.sessionKey, await validate()
            else { return nil }
            let adopt: ((String) async throws -> Void)?
            if inquiry.operation == .polish, presentedDocumentMode != .read {
                adopt = { [weak self, weak chat] replacement in
                    guard let self, let chat, !self.windowCloseCoordinator.isFinalized, self.chatController === chat,
                        self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                        self.presentedDocumentMode != .read,
                        self.currentNote?.workspaceSnapshot?.capabilities.canEditSource == true,
                        let range = attachment.sourceRange
                    else { throw AgentChatNoteMaterialError.changedSource }
                    let session = self.documentController.session(for: descriptor)
                    guard session.conflict == nil else { throw AgentChatNoteMaterialError.changedSource }
                    guard !session.editorSession.isComposing else { throw AgentChatNoteMaterialError.composing }
                    let generation = session.editorSession.generation
                    let snapshot = try await session.editorSession.currentTextSnapshot()
                    guard !self.windowCloseCoordinator.isFinalized,
                        self.documentController.retainedSession(for: descriptor.sessionKey) === session,
                        snapshot.generation == generation, session.editorSession.generation == generation,
                        !session.editorSession.isComposing,
                        self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                        self.presentedDocumentMode != .read, session.conflict == nil,
                        DocumentFingerprint(content: snapshot.text) == attachment.fingerprint,
                        let webView = session.editorSession.webView
                    else { throw AgentChatNoteMaterialError.changedSource }
                    _ = try await session.editorSession.send(
                        .replacePassage(
                            expectedText: snapshot.text,
                            fromUTF16: range.utf16LowerBound, toUTF16: range.utf16UpperBound, replacement: replacement, preserveSelection: false), in: webView)
                }
            } else {
                adopt = nil
            }
            var conversationsByVersion: [String: UUID] = [:]
            let result = AgentSelectionResult(
                title: inquiry.title, original: attachment.text, adopt: adopt,
                openReference: { [weak self, weak chat] url in
                    guard let self, let chat, self.chatController === chat else { return false }
                    return self.openChatReference(url)
                },
                generate: { [weak self, weak chat] in
                    guard let chat, self?.chatController === chat,
                        WritingAssistancePreferences.shared.model == model, let operation = inquiry.operation
                    else { throw CancellationError() }
                    guard chat.connectionState == .ready, chat.account != nil else {
                        throw SelectionWritingError.notConnected
                    }
                    let reply = try await chat.writingAssistance(
                        operation: operation,
                        passage: attachment.text,
                        model: model
                    )
                    guard self?.chatController === chat, WritingAssistancePreferences.shared.model == model else { throw CancellationError() }
                    return reply
                },
                continueInChat: { [weak self, weak chat] reply in
                    guard let self, let chat, self.chatController === chat else { return }
                    let version = reply ?? ""
                    if let id = conversationsByVersion[version], chat.conversations.contains(where: { $0.id == id && $0.isAvailable }) {
                        chat.select(id)
                        chat.presentContext(in: id)
                    } else {
                        chat.newConversation()
                        guard let id = chat.selectedID else { return }
                        var question = inquiry.question ?? inquiry.title
                        if let reply {
                            question += "\n\n" + ScholiumL10n.string("AI-generated suggestion for discussion:") + "\n" + reply
                        }
                        guard chat.prepareSelectionInquiry([attachment], inquiry: .init(title: inquiry.title, question: question), to: id) else { return }
                        conversationsByVersion[version] = id
                    }
                    continueInChat()
                })
            selectionResult = (inquiry, attachment, model, result)
            result.regenerate()
            return result
        } catch is CancellationError {
            return nil
        } catch {
            guard chatController === chat, currentDocumentDescriptor?.sessionKey == descriptor.sessionKey, !Task.isCancelled else { return nil }
            throw error
        }
    }

    @MainActor
    private func currentSelectionAttachment() async throws -> AgentChatAttachment {
        guard let note = currentNote?.hydratedSnapshot, let descriptor = currentDocumentDescriptor,
            let noteID = note.stableIdentity.resolvedID
        else { throw AgentChatNoteMaterialError.selectionUnavailable }
        let session = documentController.session(for: descriptor)
        let mode = presentedDocumentMode
        let snapshot: MarkdownSourceSelectionSnapshot
        if mode == .read {
            guard !session.hasUnsavedChanges,
                session.renderedReadFingerprint == note.document.fingerprint.sha256,
                let selection = session.readSelection,
                let captured = MarkdownReviewSourceSelection.review(selection, source: note.document.rawContent)
            else { throw AgentChatNoteMaterialError.selectionUnavailable }
            snapshot = captured
        } else {
            snapshot = try await session.editorSession.selectedSourceSnapshot()
        }
        guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey, presentedDocumentMode == mode else {
            throw AgentChatNoteMaterialError.selectionUnavailable
        }
        return .init(
            noteID: noteID, vaultID: descriptor.reference.vaultID,
            relativePath: note.id.relativePath, text: snapshot.excerpt, fingerprint: DocumentFingerprint(content: snapshot.source),
            sourceLine: snapshot.line, sourceRange: snapshot.sourceRange,
            source: mode == .read ? .savedSource : .editorSnapshot, vaultRole: descriptor.reference.vaultRole)
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
            chat.selectedID.map({ !chat.preparingMaterials.contains($0) }) ?? true
        else { return false }
        return items.allSatisfy { (try? AgentChatPasteboardSnapshot.resolve($0, in: notes)) != nil }
    }

    @MainActor @discardableResult
    func addNotesToChat(_ items: [SidebarNoteDragItem]) -> Bool {
        guard canAddNotesToChat(items), let chat = chatController,
            let runtime = windowWorkspaceController.activeCapabilities?.runtimeIdentity
        else { return false }
        if chat.selected == nil || chat.selected?.isAvailable == false { chat.newConversation() }
        guard let conversationID = chat.selectedID else { return false }
        chat.presentContext(in: conversationID)
        Task { @MainActor [weak self, weak chat] in
            guard let self, let chat, self.chatController === chat,
                self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime
            else { return }
            await chat.addTransferredMaterials(
                items.map(AgentChatTransferredMaterial.note), origin: .drop,
                to: conversationID
            ) { [weak self] item in
                guard let self, self.chatController === chat,
                    self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime
                else { throw CancellationError() }
                let note = try AgentChatPasteboardSnapshot.resolve(item, in: self.workspaceCatalog?.notes ?? [])
                try await self.addNoteToChat(note, conversationID: conversationID)
            }
        }
        return true
    }

    @MainActor
    func addNoteToChat(_ note: WorkspaceCatalogNote, conversationID: UUID) async throws {
        guard let chat = chatController,
            chat.conversations.contains(where: { $0.id == conversationID && $0.isAvailable == true }),
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
            do { text = try await retained.editorSession.currentTextSnapshot().text } catch is CancellationError { throw CancellationError() } catch {
                throw AgentChatNoteMaterialError.editorUnavailable
            }
            guard documentController.retainedSession(for: key) === retained,
                !retained.editorSession.isComposing
            else { throw AgentChatNoteMaterialError.editorUnavailable }
            source = .editorSnapshot
        } else {
            text = document.rawContent
            source = .savedSource
        }
        try Task.checkCancellation()
        guard chatController === chat,
            windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
            workspaceCatalog?.notes.contains(where: { $0.reference == reference }) == true
        else { throw AgentChatNoteMaterialError.changedSource }
        guard
            chat.attachContext(
                [
                    .init(
                        noteID: noteID, vaultID: reference.vaultID,
                        relativePath: reference.relativePath, text: text, fingerprint: DocumentFingerprint(content: text),
                        sourceLine: 1, extent: .wholeNote, source: source, vaultRole: reference.vaultRole)
                ], to: conversationID)
        else { throw AgentChatNoteMaterialError.unavailable }
    }

    @MainActor
    func agentNoteDisplayState(canDisplay: Bool) -> AgentNoteDisplayWindow.State? {
        guard let triptych = workspaceAssignment?.id else { return nil }
        let visibleConversation = shellState.libraryVisible && shellState.sidebarContent == .chat ? chatController?.selectedID : nil
        return .init(triptychID: triptych, canDisplay: canDisplay && shellState.hasCompletedInitialRestore, visibleConversationID: visibleConversation)
    }

    @MainActor
    func displayAgentNote(_ display: AgentNoteDisplayTarget, admitted: @escaping @MainActor () -> Bool) async throws {
        guard workspaceAssignment?.id == display.triptychID,
            let runtime = windowWorkspaceController.activeCapabilities?.runtimeIdentity,
            let capabilities = windowWorkspaceController.activeCapabilities
        else { throw WorkspaceStore.displayUnavailable() }
        let matches =
            workspaceCatalog?.notes.filter {
                $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == display.noteID
                    && $0.reference.vaultID == display.note.vaultID && $0.reference.relativePath == display.note.relativePath
            } ?? []
        guard matches.count == 1, let candidate = matches.first, candidate.fingerprint == display.fingerprint else {
            throw AgentChatNoteMaterialError.changedSource
        }
        let reference = candidate.reference
        let target = DocumentSessionKey(vaultID: display.note.vaultID, noteID: display.noteID)
        let origin = currentDocumentDescriptor?.sessionKey
        let mode = presentedDocumentMode
        let cancellation = AgentNoteDisplayCancellation()
        let validate: @MainActor @Sendable () throws -> Void = { [self] in
            guard !cancellation.cancelled, admitted(), workspaceAssignment?.id == display.triptychID,
                windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime,
                currentDocumentDescriptor?.sessionKey == origin, presentedDocumentMode == mode
            else { throw WorkspaceStore.displayUnavailable() }
            for key in Set([origin, target].compactMap { $0 }) {
                if let session = documentController.retainedSession(for: key),
                    session.hasUnsavedChanges || session.editorSession.isComposing || session.conflict != nil
                {
                    throw AgentChatNoteMaterialError.editorUnavailable
                }
            }
        }
        try Task.checkCancellation()
        try validate()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                cancellation.continuation = continuation
                enqueueCurrencyAwareDocumentTransition(
                    retainingCurrentDocument: target, validateBeforePreparation: validate,
                    { isCurrent in
                        try validate()
                        guard isCurrent() else { throw CancellationError() }
                        let source = try await capabilities.documents.load(display.note)
                        try validate()
                        guard isCurrent() else { throw CancellationError() }
                        guard source.fingerprint == display.fingerprint else { throw AgentChatNoteMaterialError.changedSource }
                        if let range = display.range, let excerpt = display.excerpt {
                            guard
                                let exact = Range(
                                    NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound), in: source.rawContent),
                                source.rawContent[exact].utf8.elementsEqual(excerpt.utf8)
                            else { throw AgentChatNoteMaterialError.changedSource }
                        }
                        if origin != target {
                            try await self.activateWorkspaceReference(
                                reference, tabActivation: .place(.newTab),
                                validateDisplay: {
                                    try validate()
                                    guard isCurrent() else { throw CancellationError() }
                                })
                        }
                        guard isCurrent(), !cancellation.cancelled, admitted(), self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime,
                            self.currentDocumentDescriptor?.sessionKey == target
                        else { throw WorkspaceStore.displayUnavailable() }
                        let status = try await self.chatSourceLocationStatus(
                            reference: reference, target: target, line: display.range?.line,
                            revision: display.fingerprint.sha256, mode: mode, sourceRange: display.range, excerpt: display.excerpt)
                        guard status == .current, isCurrent(), !cancellation.cancelled, admitted(), self.currentDocumentDescriptor?.sessionKey == target else {
                            throw AgentChatNoteMaterialError.changedSource
                        }
                        self.documentController.requestSourceLocation(
                            line: display.range?.line, range: display.range,
                            requiresExactSelection: display.range != nil, sourceFingerprint: display.fingerprint.sha256)
                        if origin != target {
                            self.requestPresentationMode = self.currentNote?.workspaceSnapshot?.capabilities.canEditSource == true ? mode : nil
                        }
                    }, didFail: { cancellation.finish(.failure($0)) }, didSucceed: { cancellation.finish(.success(())) },
                    didFinish: { cancellation.finish(.failure(CancellationError())) })
            }
        } onCancel: {
            Task { @MainActor in
                cancellation.cancelled = true
                cancellation.finish(.failure(CancellationError()))
            }
        }
    }

    @MainActor
    func openChatAttachment(
        _ attachment: AgentChatAttachment, disposition: WindowOpenDisposition = .replaceCurrent
    ) async {
        _ = openChatSource(
            noteID: attachment.noteID, vaultID: attachment.vaultID,
            line: attachment.sourceLine, revision: attachment.fingerprint.sha256,
            sourceRange: attachment.sourceRange, excerpt: attachment.text, disposition: disposition)
    }

    @MainActor @discardableResult
    func openChatReference(_ url: URL, disposition: WindowOpenDisposition = .replaceCurrent) -> Bool {
        guard let reference = AgentChatReference.parse(url) else { return false }
        return openChatSource(
            noteID: reference.noteID, vaultID: reference.vaultID,
            line: reference.line, revision: reference.revision, disposition: disposition)
    }

    @MainActor private func openChatSource(
        noteID: UUID, vaultID: UUID?, line: Int?, revision: String?, sourceRange: SearchSourceRange? = nil, excerpt: String? = nil,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) -> Bool {
        let matches =
            workspaceCatalog?.notes.filter {
                $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == noteID
                    && (vaultID == nil || $0.reference.vaultID == vaultID)
            } ?? []
        guard matches.count == 1, let reference = matches.first?.reference,
            let runtime = windowWorkspaceController.activeCapabilities?.runtimeIdentity
        else {
            reportOperationIssue(String(localized: "This note cannot be located in the current Triptych."), kind: .information)
            return false
        }
        if disposition == .separateWindow {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let destination = try await workspaceStore.documentLocations.openSeparate(reference, from: self)
                    _ = destination.openChatSource(
                        noteID: noteID, vaultID: vaultID, line: line,
                        revision: revision, sourceRange: sourceRange, excerpt: excerpt)
                } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
            }
            return true
        }
        if let owner = workspaceStore.documentLocations.existingOwner(of: reference, excluding: self) {
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            return owner.openChatSource(
                noteID: noteID, vaultID: vaultID, line: line,
                revision: revision, sourceRange: sourceRange, excerpt: excerpt)
        }
        let target = DocumentSessionKey(vaultID: reference.vaultID, noteID: noteID)
        let navigationMode = presentedDocumentMode
        enqueueDocumentTransition(
            preparation: openingPreparation(for: reference, placement: disposition == .newTab ? .newTab : .replaceSelected),
            retainingCurrentDocument: target
        ) { [weak self] in
            guard let self, self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime else {
                throw CancellationError()
            }
            let alreadyCurrent = self.currentDocumentDescriptor?.sessionKey == target
            if !alreadyCurrent {
                try await self.activateWorkspaceReference(
                    reference,
                    tabActivation: .place(disposition == .newTab ? .newTab : .replaceSelected))
            }
            let canEdit = self.currentNote?.workspaceSnapshot?.capabilities.canEditSource == true
            let status = try await self.chatSourceLocationStatus(
                reference: reference, target: target,
                line: line, revision: revision, mode: canEdit ? navigationMode : .read, sourceRange: sourceRange, excerpt: excerpt)
            try Task.checkCancellation()
            guard self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime,
                self.currentDocumentDescriptor?.sessionKey == target
            else { throw CancellationError() }
            self.documentController.requestSourceLocation(
                line: status == .current ? line : nil,
                range: status == .current ? sourceRange : nil, requiresExactSelection: sourceRange != nil,
                sourceFingerprint: status == .current ? revision : nil)
            if !alreadyCurrent { self.requestPresentationMode = canEdit ? navigationMode : nil }
            switch status {
            case .current, .identity: break
            case .changed:
                self.reportOperationIssue(
                    String(localized: "This reference is from a different version. The Note was opened without selecting a passage.", bundle: .module),
                    kind: .information)
            case .unverified:
                self.reportOperationIssue(
                    String(localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module),
                    kind: .information)
            }
        }
        return true
    }

    @MainActor private func chatSourceLocationStatus(
        reference: VaultNoteReference, target: DocumentSessionKey,
        line: Int?, revision: String?, mode: NotePresentationMode, sourceRange: SearchSourceRange?, excerpt: String?
    ) async throws -> ChatSourceLocationStatus {
        guard let revision else { return line == nil ? .identity : .unverified }
        let session = documentController.session(for: target)
        guard !session.editorSession.isComposing else { return .unverified }
        let text: String
        if mode != .read, session.retainsEditorSurface, session.editorSession.isReady, session.editorSession.isLoaded {
            do {
                let snapshot = try await session.editorSession.currentTextSnapshot()
                guard documentController.retainedSession(for: target) === session,
                    snapshot.generation == session.editorSession.generation, !session.editorSession.isComposing
                else { return .unverified }
                text = snapshot.text
            } catch is CancellationError { throw CancellationError() } catch { return .unverified }
        } else {
            guard !session.hasUnsavedChanges else { return .unverified }
            do {
                let document = try await documentController.load(.init(vaultID: reference.vaultID, relativePath: reference.relativePath))
                guard !session.hasUnsavedChanges, !session.editorSession.isComposing else { return .unverified }
                if document.fingerprint.sha256 != revision { return .changed }
                guard currentNote?.workspaceSnapshot?.fingerprint == document.fingerprint else { return .unverified }
                text = document.rawContent
            } catch is CancellationError { throw CancellationError() } catch { return .unverified }
        }
        guard DocumentFingerprint(content: text).sha256 == revision else { return .changed }
        if let sourceRange {
            let lower = sourceRange.utf16LowerBound
            let upper = sourceRange.utf16UpperBound
            guard lower >= 0, upper > lower, upper <= text.utf16.count,
                let range = Range(NSRange(location: lower, length: upper - lower), in: text),
                let excerpt, text[range].utf8.elementsEqual(excerpt.utf8)
            else { return .unverified }
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

@MainActor private final class AgentNoteDisplayCancellation {
    var cancelled = false
    var continuation: CheckedContinuation<Void, Error>?
    func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

private enum SelectionWritingError: LocalizedError {
    case notConnected
    var errorDescription: String? {
        ScholiumL10n.string("Connect and sign in to Codex in Agents & Chat to use writing assistance.")
    }
}
