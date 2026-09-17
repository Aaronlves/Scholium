import Foundation
import ScholiumContracts

extension WindowModel {
    @MainActor private var relatedMaterialChat: (any AgentChatContextReceiving)? { chatController }

    @MainActor
    var canFindWritingReferences: Bool {
        currentDocumentDescriptor != nil && presentedDocumentMode != .read && !isDetachedDocumentWindow
    }

    @MainActor
    func findRelatedMaterials(automatic: Bool = false, paragraph: Bool = true, refreshIndex: Bool = false) {
        let materials = researchController.relatedMaterials
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            let descriptor = currentDocumentDescriptor, let note = currentNote
        else {
            materials.report(RelatedMaterialsError.unavailable)
            return
        }
        let editor = documentController.session(for: descriptor).editorSession
        guard !automatic || ((paragraph || editor.hasNonemptySelection) && editor.hasWritingFocus && !editor.isComposing && presentedDocumentMode != .read)
        else { return }
        materials.find(
            capture: { [weak self] in
                let selection: MarkdownSourceSelectionSnapshot
                let captured = try await editor.writingContextSnapshot(paragraph: paragraph)
                selection = captured.snapshot
                guard let self,
                    self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                    self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity
                else {
                    throw CancellationError()
                }
                let seed = RelatedContentSeedSnapshot(
                    noteID: VaultQualifiedNoteID(vaultID: descriptor.reference.vaultID, relativePath: note.relativePath),
                    source: selection.source,
                    focuses: [.init(kind: .selectedPassage, text: selection.excerpt)])
                return RelatedMaterialsSeed(
                    request: .init(seed: seed),
                    attachment: .init(
                        noteID: descriptor.sessionKey.noteID, vaultID: descriptor.reference.vaultID, relativePath: note.relativePath,
                        text: selection.excerpt, fingerprint: seed.fingerprint, sourceLine: selection.line,
                        sourceRange: selection.sourceRange, vaultRole: descriptor.reference.vaultRole),
                    insertionPoint: captured.point, usesParagraph: captured.point != nil)
            },
            retrieve: { [discovery = capabilities.discovery] request in
                if refreshIndex { _ = try await discovery.refresh() }
                let response = try await discovery.relatedContent(request)
                guard response.state == .stale, !refreshIndex else { return response }
                try Task.checkCancellation()
                _ = try await discovery.refresh()
                try Task.checkCancellation()
                return try await discovery.relatedContent(request)
            }, references: workspaceCatalog?.notes.map(\.reference) ?? [], automatic: automatic,
            canPublish: { [weak self] in
                guard let self,
                    self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                    self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity
                else { return false }
                return !automatic || (editor.hasWritingFocus && !editor.isComposing && self.presentedDocumentMode != .read)
            },
            linkTarget: { [weak self] reference in
                guard let self else { return nil }
                return await self.relatedLinkTarget(reference, from: descriptor)
            })
    }

    @MainActor
    func retryRelatedMaterials() {
        findRelatedMaterials(paragraph: true, refreshIndex: researchController.relatedMaterials.needsRefresh)
    }

    @MainActor private func relatedLinkTarget(_ reference: VaultNoteReference, from descriptor: WindowDocumentDescriptor) async -> String? {
        guard let catalog = workspaceCatalog,
            let candidate = catalog.notes.first(where: { $0.reference == reference })
        else { return nil }
        let items = await documentController.editorLinkCompletions(
            kind: .wikilink, matching: candidate.title, sourcePath: descriptor.reference.relativePath,
            currentVaultID: descriptor.reference.vaultID, catalogNotes: catalog.notes,
            graphGeneration: catalog.graph?.generation ?? 0)
        return items.first { !$0.isAmbiguous && $0.path == "\(reference.vaultName)/\(reference.relativePath)" }?.insertion
    }

    @MainActor
    func insertRelatedMaterialLink(_ card: RelatedMaterialCard) async {
        let materials = researchController.relatedMaterials
        guard canFindWritingReferences, !materials.isLoading, !materials.isInsertingParagraphLink,
            let descriptor = currentDocumentDescriptor, let point = materials.insertionPoint,
            let seed = materials.seed,
            seed.request.seed.noteID == VaultQualifiedNoteID(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath)
        else {
            materials.report(RelatedMaterialsError.insertionChanged)
            return
        }
        let editor = documentController.session(for: descriptor).editorSession
        do {
            guard let target = await relatedLinkTarget(card.reference, from: descriptor),
                materials.seed?.request.id == seed.request.id, materials.insertionPoint == point,
                editor.acceptsInsertionPoint(point)
            else { throw RelatedMaterialsError.insertionChanged }
            try await editor.insertReference(target, at: point)
        } catch {
            guard materials.seed?.request.id == seed.request.id else { return }
            materials.invalidateWritingContext()
            materials.report(RelatedMaterialsError.insertionChanged)
        }
    }

    @MainActor
    func insertRelatedMaterialParagraphLink(_ card: RelatedMaterialCard) async {
        let materials = researchController.relatedMaterials
        guard canFindWritingReferences, let descriptor = currentDocumentDescriptor,
            let point = materials.insertionPoint, let seed = materials.seed,
            let capabilities = windowWorkspaceController.activeCapabilities,
            seed.request.seed.noteID == .init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath),
            card.candidate.note != seed.request.seed.noteID,
            materials.beginParagraphInsertion(card)
        else { return }
        defer { materials.finishParagraphInsertion() }
        let editor = documentController.session(for: descriptor).editorSession
        var savedNewAnchor = false
        func validateDestination() throws {
            guard canFindWritingReferences,
                currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                materials.seed?.request.id == seed.request.id, materials.insertionPoint == point,
                editor.acceptsInsertionPoint(point),
                workspaceCatalog?.notes.contains(where: { $0.reference == card.reference }) == true
            else { throw RelatedMaterialsError.insertionChanged }
        }
        do {
            try validateDestination()
            guard let noteLink = await relatedLinkTarget(card.reference, from: descriptor) else {
                throw RelatedMaterialsError.changedSource
            }
            try validateDestination()
            let vaults = try await capabilities.documents.snapshot()
            guard
                let source = vaults.first(where: { $0.vault.id == card.reference.vaultID })?.documents.first(where: {
                    $0.id == card.candidate.note && $0.stableIdentity.resolvedID?.uuidString.lowercased() == card.reference.stableNoteID?.lowercased()
                }), source.capabilities.canEditSource, let sourceID = source.stableIdentity.resolvedID
            else { throw RelatedMaterialsError.changedSource }
            let document = try await capabilities.documents.load(card.candidate.note)
            let plan = try RelatedParagraphLink.plan(for: card, in: document)
            let key = DocumentSessionKey(vaultID: card.reference.vaultID, noteID: sourceID)
            let owner = workspaceStore.documentLocations.existingOwner(of: card.reference, excluding: self) ?? self
            let sourceSession = owner.documentController.retainedSession(for: key)
            func validateSourceOwner() throws {
                let currentOwner = workspaceStore.documentLocations.existingOwner(of: card.reference, excluding: self) ?? self
                guard currentOwner === owner, !owner.transferInProgress,
                    owner.documentController.retainedSession(for: key) === sourceSession,
                    sourceSession?.hasUnsavedChanges != true, sourceSession?.conflict == nil,
                    sourceSession?.editorSession.isComposing != true
                else { throw RelatedMaterialsError.changedSource }
            }
            try validateSourceOwner()
            if let sourceSession, sourceSession.isEditing, sourceSession.editorSession.hasAttachedWebView {
                let current = try await sourceSession.editorSession.currentText()
                guard current.utf8.elementsEqual(document.rawContent.utf8) else { throw RelatedMaterialsError.changedSource }
            }
            try validateDestination()
            try validateSourceOwner()
            if let edit = plan.edits.first {
                if let sourceSession, sourceSession.isEditing, sourceSession.editorSession.hasAttachedWebView {
                    let sourceEditor = sourceSession.editorSession
                    guard let webView = sourceEditor.webView, plan.edits.count == 1 else { throw RelatedMaterialsError.changedSource }
                    let bytes = Array(document.rawContent.utf8)
                    let from = String(decoding: bytes[..<edit.startUTF8], as: UTF8.self).utf16.count
                    let to = String(decoding: bytes[..<edit.endUTF8], as: UTF8.self).utf16.count
                    _ = try await sourceEditor.send(
                        .replacePassage(
                            expectedText: document.rawContent, fromUTF16: from, toUTF16: to,
                            replacement: edit.replacement, preserveSelection: true), in: webView)
                    try await owner.documentController.flushForExternalOperation(
                        session: sourceSession, target: .workspace(key),
                        onCommitted: { committed in
                            if ParagraphAnchorPlanner.anchors(in: committed).contains(where: { $0.id == plan.anchorID }) {
                                savedNewAnchor = true
                            }
                        })
                } else {
                    _ = try await capabilities.documents.save(
                        card.candidate.note, changeSet: .source(plan.candidateSource), expectedRevision: document.fingerprint)
                    savedNewAnchor = true
                }
            }
            guard await relatedLinkTarget(card.reference, from: descriptor) == noteLink else {
                throw RelatedMaterialsError.changedSource
            }
            let saved = try await capabilities.documents.load(card.candidate.note)
            try RelatedParagraphLink.verify(plan, saved: saved)
            if !plan.edits.isEmpty { savedNewAnchor = true }
            if let sourceSession, !sourceSession.editorSession.hasAttachedWebView {
                guard let savedSnapshot = try await owner.documentController.noteSnapshot(card.candidate.note),
                    savedSnapshot.fingerprint == saved.fingerprint,
                    savedSnapshot.stableIdentity.resolvedID == sourceID
                else { throw RelatedMaterialsError.changedSource }
                try validateSourceOwner()
                owner.documentController.recordCommittedSnapshot(
                    savedSnapshot, vaultName: card.reference.vaultName, vaultRole: card.reference.vaultRole)
            }
            if let sourceSession, sourceSession.isEditing, sourceSession.editorSession.hasAttachedWebView {
                let current = try await sourceSession.editorSession.currentText()
                guard current.utf8.elementsEqual(saved.rawContent.utf8), !sourceSession.hasUnsavedChanges else {
                    throw RelatedMaterialsError.changedSource
                }
            }
            try validateDestination()
            try validateSourceOwner()
            // Completion supplies a bare, unambiguous target; the editor owns syntax
            // insertion and the single destination Undo transaction.
            try await editor.insertReference("\(noteLink)#^\(plan.anchorID)", at: point)
        } catch {
            guard materials.seed?.request.id == seed.request.id else {
                if savedNewAnchor { reportOperationIssue(RelatedMaterialsError.anchorSavedWithoutLink.localizedDescription, kind: .error) }
                return
            }
            if savedNewAnchor {
                materials.report(RelatedMaterialsError.anchorSavedWithoutLink)
            } else {
                materials.report(error)
            }
        }
    }

    /// The handoff speaks only in Note snapshots and generic chat context.
    /// Provider selection and runtime transport remain owned by Chat.
    @MainActor
    func useRelatedMaterial(_ card: RelatedMaterialCard, inChat: Bool) async -> Bool {
        let materials = researchController.relatedMaterials
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            let seed = materials.seed
        else { return false }
        do {
            if !inChat {
                guard
                    let current = workspaceCatalog?.notes.first(where: {
                        $0.reference.vaultID == card.reference.vaultID && $0.reference.relativePath == card.reference.relativePath
                    })
                else { throw RelatedMaterialsError.changedSource }
                await openWorkspaceReference(
                    current.reference,
                    line: card.passage.range.line, inspectorMode: .related,
                    sourceFingerprint: card.candidate.fingerprint)
                return true
            }
            let document = try await capabilities.documents.load(card.candidate.note)
            guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                materials.seed?.request.id == seed.request.id
            else { return false }
            guard document.fingerprint == card.candidate.fingerprint,
                workspaceCatalog?.notes.contains(where: { $0.reference == card.reference }) == true
            else {
                throw RelatedMaterialsError.changedSource
            }
            if let id = card.reference.stableNoteID.flatMap(UUID.init(uuidString:)),
                let retained = documentController.retainedSession(for: .init(vaultID: card.reference.vaultID, noteID: id)),
                retained.hasUnsavedChanges
            {
                throw RelatedMaterialsError.changedSource
            }
            if inChat {
                guard let attachment = card.attachment, let receiver = relatedMaterialChat,
                    receiver.attachContext([seed.attachment, attachment])
                else {
                    throw RelatedMaterialsError.chatUnavailable
                }
            } else {
                await openWorkspaceReference(card.reference, line: card.passage.range.line, inspectorMode: .related)
            }
            return true
        } catch {
            guard materials.seed?.request.id == seed.request.id else { return false }
            materials.report(error)
            return false
        }
    }
}
