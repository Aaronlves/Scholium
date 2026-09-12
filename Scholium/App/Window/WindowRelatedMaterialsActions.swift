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
            canPublish: { !automatic || (editor.hasWritingFocus && !editor.isComposing) },
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
        guard canFindWritingReferences, !materials.isLoading, let descriptor = currentDocumentDescriptor, let point = materials.insertionPoint,
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
            materials.invalidateWritingContext()
            materials.report(RelatedMaterialsError.insertionChanged)
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
                let document = try await capabilities.documents.load(card.candidate.note)
                guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                    materials.seed?.request.id == seed.request.id
                else { return false }
                let dirtySource =
                    current.reference.stableNoteID.flatMap(UUID.init(uuidString:)).flatMap {
                        documentController.retainedSession(for: .init(vaultID: current.reference.vaultID, noteID: $0))
                    }?.hasUnsavedChanges == true
                await openWorkspaceReference(
                    current.reference,
                    line: !dirtySource && document.fingerprint == card.candidate.fingerprint ? card.passage.range.line : nil,
                    inspectorMode: .related)
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
            materials.report(error)
            return false
        }
    }
}
