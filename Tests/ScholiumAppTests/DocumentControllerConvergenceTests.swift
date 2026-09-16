import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Document controller convergence")
@MainActor
struct DocumentControllerConvergenceTests {
    enum ReloadInterleaving: CaseIterable { case unchanged, newerConflict, sourceNormalization }

    @Test("Reload completes only the accepted conflict and preserves concurrent changes", arguments: ReloadInterleaving.allCases)
    func conflictReloadCompletion(interleaving: ReloadInterleaving) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/conflict-reload-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let base = "Original\n"
        let draft = "Researcher's unsaved café\n"
        let normalizedDraft = draft.replacingOccurrences(of: "é", with: "e\u{301}")
        let accepted = "Accepted disk revision\n"
        let later = "Newer external revision\n"
        let file = vaults[1].appendingPathComponent("Source.md")
        try Data(accepted.utf8).write(to: file)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Conflict reload fixture")
            let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
            let snapshot = try #require(vault.documents.first { $0.id.relativePath == "Source.md" })
            let controller = DocumentController()
            controller.installOpenedDocument(snapshot, vaultName: "Topics", vaultRole: .topicKnowledge)
            let descriptor = try #require(controller.activeDocument)
            let target = DocumentEditingTarget.workspace(descriptor.sessionKey)
            let session = controller.session(for: descriptor)
            defer { session.cancelScheduledWork() }
            controller.beginEditing(
                session: session, target: target, source: base,
                revision: DocumentFingerprint(content: base), mode: .source)
            session.editingSource = draft
            session.conflict = .init(
                relativePath: "Source.md", editorSource: draft,
                diskSource: accepted, baseRevision: DocumentFingerprint(content: base))
            session.presentConflictComparison()
            let newerConflict = DocumentConflictSnapshot(
                relativePath: "Source.md", editorSource: draft,
                diskSource: later, baseRevision: DocumentFingerprint(content: base))
            controller.bind(
                to: capabilities.documents,
                documentDidCommit: { _ in
                    if interleaving == .newerConflict {
                        // This existing publication callback runs after load and before
                        // the reload continuation can replace the editor's source.
                        do { try Data(later.utf8).write(to: file) } catch { Issue.record(error) }
                        session.conflict = newerConflict
                    } else if interleaving == .sourceNormalization {
                        session.editingSource = normalizedDraft
                    }
                })
            if interleaving == .newerConflict {
                await #expect(throws: VaultRepositoryError.self) {
                    try await controller.reloadFromDisk(session: session, target: target)
                }
                #expect(session.conflict == newerConflict)
                #expect(session.editingSource == draft && session.isEditing)
                #expect(try Data(contentsOf: file) == Data(later.utf8))
            } else if interleaving == .sourceNormalization {
                await #expect(throws: VaultRepositoryError.self) {
                    try await controller.reloadFromDisk(session: session, target: target)
                }
                #expect(session.isEditing && session.conflict != nil)
                #expect(session.editingSource.utf8.elementsEqual(normalizedDraft.utf8))
                #expect(!session.editingSource.utf8.elementsEqual(draft.utf8))
                #expect(try Data(contentsOf: file) == Data(accepted.utf8))
            } else {
                try await controller.reloadFromDisk(session: session, target: target)
                #expect(session.conflict == nil && session.editError == nil)
                #expect(!session.isEditing && !session.hasUnsavedChanges)
                #expect(session.editingSource == accepted && session.editorSession.checkedSource == accepted)
                #expect(try Data(contentsOf: file) == Data(accepted.utf8))
            }
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("Review completion rejects input accepted after the saved snapshot", arguments: [false, true])
    func reviewCompletionChecksLatestBuffer(lateInput: Bool) async throws {
        let vault = UUID()
        let id = UUID()
        let original = note(vaultID: vault, noteID: id, path: "Draft.md", source: "Saved source\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Works", vaultRole: .draftProject)
        let target = DocumentEditingTarget.workspace(.init(vaultID: vault, noteID: id))
        let session = controller.session(for: target)
        controller.beginEditing(
            session: session, target: target, source: original.document.rawContent,
            revision: original.fingerprint, mode: .source)
        let captured = AsyncStream<Void>.makeStream()
        let acknowledgement = AsyncStream<Void>.makeStream()
        defer {
            captured.continuation.finish()
            acknowledgement.continuation.finish()
            session.cancelScheduledWork()
        }
        // Existing save-task admission supplies the deterministic suspension:
        // source capture is complete, but the caller has not yet received its receipt.
        session.activeSaveTask = Task { @MainActor in
            captured.continuation.yield(())
            for await _ in acknowledgement.stream { break }
            return .clean
        }
        let handoff = Task { @MainActor in
            try await controller.flushForExternalOperation(session: session, target: target)
            session.activeSaveTask = nil
            try controller.finishEditing(session: session, target: target)
        }
        for await _ in captured.stream { break }
        if lateInput { session.editingSource = "Late researcher input\n" }
        acknowledgement.continuation.yield(())
        if lateInput {
            await #expect(throws: DocumentControllerError.changedDuringSave) { try await handoff.value }
            #expect(session.isEditing && session.hasUnsavedChanges)
            #expect(session.editingSource == "Late researcher input\n")
            #expect(session.editingRevision == original.fingerprint)
        } else {
            try await handoff.value
            #expect(!session.isEditing && !session.hasUnsavedChanges)
        }
    }

    @Test("A dirty Review buffer cannot receive a successful close or quit flush")
    func dirtyReviewCannotFlushAsClean() async throws {
        let controller = DocumentController()
        let target = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let session = controller.session(for: target)
        session.originalEditingSource = "Saved\n"
        session.editingSource = "Unsaved retained input\n"
        #expect(!session.isEditing)
        await #expect(throws: DocumentControllerError.changedDuringSave) {
            try await controller.flushForExternalOperation(session: session, target: target)
        }
        #expect(session.hasUnsavedChanges)
        #expect(session.editingSource == "Unsaved retained input\n")
    }

    @Test("A finished rename retry releases admission for later autosaves")
    func renameRetryReleasesAutosave() async throws {
        let vault = UUID()
        let id = UUID()
        let original = note(vaultID: vault, noteID: id, path: "Draft.md", source: "Saved\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Works", vaultRole: .draftProject)
        let key = DocumentSessionKey(vaultID: vault, noteID: id)
        let target = DocumentEditingTarget.workspace(key)
        let session = controller.session(for: target)
        controller.beginEditing(
            session: session, target: target, source: original.document.rawContent,
            revision: original.fingerprint, mode: .source)
        defer { session.cancelScheduledWork() }
        session.editingSource = "Pending edit\n"
        session.activeSaveToken = UUID()
        session.isSavingEdit = true
        session.activeSaveTask = Task { @MainActor in
            // The joined save completes before the retry, so no further write is necessary.
            session.editingSource = session.originalEditingSource
            return .clean
        }
        controller.updateDocumentProjection(
            .init(
                sessionKey: key,
                reference: .init(
                    vaultID: vault, vaultName: "Works", vaultRole: .draftProject,
                    relativePath: "Renamed.md", stableNoteID: id.uuidString)))
        let retry = try #require(session.autosaveTask)
        let retryToken = try #require(session.autosaveToken)
        await retry.value
        #expect(session.autosaveTask == nil && session.autosaveToken == nil)
        session.suppressAutosave = false
        session.editingSource = "Next edit\n"
        controller.scheduleAutosave(session: session, target: target)
        let nextToken = try #require(session.autosaveToken)
        #expect(nextToken != retryToken && session.autosaveTask != nil)
        // A cancelled/late predecessor cannot clear the newly scheduled task.
        session.finishAutosave(token: retryToken)
        #expect(session.autosaveToken == nextToken && session.autosaveTask != nil)
    }

    @Test("External publication reconciles inactive retained editors without changing selection", arguments: [false, true])
    func inactiveExternalPublication(dirty: Bool) throws {
        let vault = UUID()
        let id = UUID()
        let original = note(vaultID: vault, noteID: id, path: "First.md", source: "Original\n")
        let other = note(vaultID: vault, noteID: UUID(), path: "Other.md", source: "Other\n")
        let external = note(vaultID: vault, noteID: id, path: "First.md", source: "External revision\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Works", vaultRole: .draftProject)
        let firstDocument = try #require(controller.selectedDocument)
        let session = controller.session(for: firstDocument.editingTarget)
        controller.beginEditing(
            session: session, target: firstDocument.editingTarget, source: original.document.rawContent,
            revision: original.fingerprint, mode: .source)
        if dirty { session.editingSource = "Researcher's draft\n" }
        controller.installOpenedDocument(other, vaultName: "Works", vaultRole: .draftProject)
        let selected = try #require(controller.selectedDocument)
        let selectedSession = controller.session(for: selected.editingTarget)
        let publication = workspace(vaultID: vault, notes: [external, other])
        controller.receive(publication, openDocuments: [firstDocument, selected])
        let current = try #require(controller.selectedDocument)
        #expect(current.editingTarget == selected.editingTarget)
        #expect(current.relativePath == selected.relativePath)
        #expect(controller.session(for: current.editingTarget) === selectedSession)
        let publishedVault = try #require(publication.vault(id: vault)?.vault)
        #expect(current.workspaceDescriptor?.reference.vaultName == publishedVault.name)
        #expect(current.workspaceDescriptor?.reference.vaultRole == publishedVault.role)
        #expect(controller.lastSaveError == nil)
        if dirty {
            #expect(session.editingSource == "Researcher's draft\n")
            #expect(session.conflict?.diskSource == external.document.rawContent)
            #expect(session.editingRevision == original.fingerprint)
        } else {
            #expect(session.editingSource == external.document.rawContent)
            #expect(session.editorSession.checkedSource == external.document.rawContent)
            #expect(session.editingRevision == external.fingerprint)
            #expect(!session.hasUnsavedChanges)
        }
        #expect(controller.selectRetainedDocument(firstDocument))
        #expect((session.conflict != nil) == dirty)
    }

    @Test("Accepted workspace updates invalidate attachment listings without replacing an unsaved document")
    func attachmentRefreshKeepsDraft() throws {
        let vault = UUID()
        let id = UUID()
        let original = note(vaultID: vault, noteID: id, path: "Analysis.md", source: "Saved source\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Analyses", vaultRole: .sourceCorpus)
        let session = try #require(controller.retainedSession(for: .init(vaultID: vault, noteID: id)))
        session.editingSource = "Researcher's unsaved draft\n"
        _ = controller.receive(workspace(vaultID: vault, notes: [original]))
        #expect(session.editingSource == "Researcher's unsaved draft\n")
        #expect(session.editingRevision == original.fingerprint)
    }

    @Test("Source navigation is document-bound and stale acknowledgements cannot consume a newer activation")
    func sourceNavigationOwnership() throws {
        let controller = DocumentController()
        let vault = UUID()
        controller.selectUnavailableDocument(vaultID: vault, relativePath: "First.md")
        controller.requestSourceLocation(line: 2)
        let old = try #require(controller.sourceLocationRequest)
        controller.selectUnavailableDocument(vaultID: vault, relativePath: "Second.md")
        #expect(controller.sourceLocationRequest == nil)
        controller.requestSourceLocation(line: 2)
        let current = try #require(controller.sourceLocationRequest)
        controller.consumeSourceLocation(old.id)
        #expect(controller.sourceLocationRequest == current)
        controller.requestSourceLocation(line: 2)
        let repeated = try #require(controller.sourceLocationRequest)
        #expect(repeated.id != current.id)
        controller.consumeSourceLocation(current.id)
        #expect(controller.sourceLocationRequest == repeated)
        controller.consumeSourceLocation(repeated.id)
        #expect(controller.sourceLocationRequest == nil)
        controller.requestSourceLocation(line: 4)
        controller.clearSelectionAfterClosingLastTab()
        #expect(controller.sourceLocationRequest == nil)
    }

    @Test("Managed creation installs exact source directly into one Edit session")
    func managedCreationStartsInEdit() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let source = "---\ntags: [draft]\n---\n"
        let created = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Untitled.md",
            source: source
        )
        let controller = DocumentController()
        controller.requestedPresentationMode = .source
        controller.selectUnavailableDocument(vaultID: vaultID, relativePath: "Previous.md")
        controller.requestSourceLocation(line: 99)

        controller.installOpenedDocument(
            created,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            managedCreationBodyStartUTF16: created.document.bodyUTF16Offset
        )

        let session = try #require(
            controller.retainedSession(
                for: .init(
                    vaultID: vaultID,
                    noteID: noteID
                )))
        #expect(controller.currentPresentationMode == .livePreview)
        #expect(controller.requestedPresentationMode == nil)
        #expect(controller.sourceLocationRequest == nil)
        #expect(session.presentationMode == .livePreview)
        #expect(session.activeEditorMode == .livePreview)
        #expect(session.retainsEditorSurface)
        #expect(session.editingSource == source)
        #expect(session.originalEditingSource == source)
        #expect(session.editingRevision == created.fingerprint)
        #expect(
            session.managedCreationBodyStartUTF16
                == source.utf16.count
        )
    }

    @Test("External source replaces a clean managed buffer before editor readiness")
    func managedCreationConvergesBeforeEditorReadiness() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let initialSource = "---\ntags: [draft]\n---\n"
        let externalSource = "---\ntags: [external]\n---\nExternal body\n"
        let controller = DocumentController()
        let created = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Untitled.md",
            source: initialSource
        )
        controller.installOpenedDocument(
            created,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            managedCreationBodyStartUTF16: created.document.bodyUTF16Offset
        )
        let session = try #require(
            controller.retainedSession(
                for: .init(
                    vaultID: vaultID,
                    noteID: noteID
                )))
        session.editorSession.loadDocument(
            initialSource,
            documentID: session.editorSession.bridgeDocumentID,
            mode: .livePreview
        )
        #expect(!session.editorSession.isLoaded)
        #expect(session.editorSession.checkedSource == initialSource)

        let external = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Untitled.md",
            source: externalSource
        )
        controller.installOpenedDocument(
            external,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus
        )

        #expect(session.editingSource == externalSource)
        #expect(session.originalEditingSource == externalSource)
        #expect(session.editingRevision == external.fingerprint)
        #expect(session.editorSession.checkedSource == externalSource)
        #expect(session.managedCreationBodyStartUTF16 == external.document.bodyUTF16Offset)
    }

    @Test("Clean peer converges while dirty peer keeps exact editor bytes")
    func cleanAndDirtyPeers() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let original = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Argument.md",
            source: "# Argument\n\nOriginal.\n"
        )
        let external = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Argument.md",
            source: "# Argument\n\nExternal revision.\n"
        )
        let dirty = DocumentController()
        let clean = DocumentController()
        dirty.installOpenedDocument(
            original,
            vaultName: "Works",
            vaultRole: .draftProject
        )
        clean.installOpenedDocument(
            original,
            vaultName: "Works",
            vaultRole: .draftProject
        )

        let key = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        let exactDirtyBuffer = "\u{FEFF}# Argument\r\n\r\nUncommitted local thought.\r\n"
        dirty.session(for: try #require(dirty.activeDocument)).editingSource = exactDirtyBuffer

        dirty.installOpenedDocument(
            external,
            vaultName: "Works",
            vaultRole: .draftProject
        )
        clean.installOpenedDocument(
            external,
            vaultName: "Works",
            vaultRole: .draftProject
        )

        let dirtySession = try #require(dirty.retainedSession(for: key))
        #expect(dirtySession.editingSource == exactDirtyBuffer)
        #expect(dirtySession.conflict?.editorSource == exactDirtyBuffer)
        #expect(dirtySession.conflict?.diskSource == external.document.rawContent)
        #expect(dirtySession.editingRevision == original.fingerprint)

        let cleanSession = try #require(clean.retainedSession(for: key))
        #expect(cleanSession.editingSource == external.document.rawContent)
        #expect(cleanSession.originalEditingSource == external.document.rawContent)
        #expect(cleanSession.editingRevision == external.fingerprint)
        #expect(cleanSession.conflict == nil)
    }

    @Test("External source cannot reload a clean editor during marked-text composition")
    func compositionProtectsEditorFromExternalReload() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let originalSource = "# Argument\n\nOriginal.\n"
        let externalSource = "# Argument\n\nExternal revision.\n"
        let original = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Argument.md",
            source: originalSource
        )
        let external = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Argument.md",
            source: externalSource
        )
        let controller = DocumentController()
        controller.installOpenedDocument(
            original,
            vaultName: "Works",
            vaultRole: .draftProject
        )
        let document = try #require(controller.activeDocument)
        let session = controller.session(for: document)
        let target = DocumentEditingTarget.workspace(
            .init(
                vaultID: vaultID,
                noteID: noteID
            ))
        controller.beginEditing(
            session: session,
            target: target,
            source: originalSource,
            revision: original.fingerprint,
            mode: .livePreview
        )
        session.editorSession.loadDocument(
            originalSource,
            documentID: session.editorSession.bridgeDocumentID,
            mode: .livePreview
        )
        let selection = MarkdownEditorSelectionRange(anchor: 0, head: 0)
        session.editorSession.updateInteraction(
            selections: [selection],
            line: 1,
            column: 1,
            lineCount: 1,
            documentVersion: session.editorSession.generation,
            context: MarkdownEditorContext(
                selections: [selection],
                activeInlineConstructs: [],
                activeBlockConstructs: [],
                tablePosition: nil,
                composing: true,
                availableCommands: [],
                undoLabel: nil,
                redoLabel: nil
            )
        )
        #expect(!session.hasUnsavedChanges)
        #expect(session.editorSession.isComposing)

        controller.installOpenedDocument(
            external,
            vaultName: "Works",
            vaultRole: .draftProject
        )

        #expect(session.editingSource == originalSource)
        #expect(session.editorSession.checkedSource == originalSource)
        #expect(session.editingRevision == original.fingerprint)
        #expect(session.conflict?.editorSource == originalSource)
        #expect(session.conflict?.diskSource == externalSource)
    }

    @Test("The latest workspace snapshot observed during a save converges after acknowledgement")
    func saveDefersAndConvergesLatestWorkspaceSnapshot() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let originalSource = "Original\n"
        let savedSource = "Saved by this session\n"
        let latestExternalSource = "Latest external source\n"
        let original = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Race.md",
            source: originalSource
        )
        let saved = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Race.md",
            source: savedSource
        )
        let latestExternal = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Race.md",
            source: latestExternalSource
        )
        let controller = DocumentController()
        controller.installOpenedDocument(
            original,
            vaultName: "Works",
            vaultRole: .draftProject
        )
        let key = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        let session = try #require(controller.retainedSession(for: key))
        session.isSavingEdit = true

        controller.installOpenedDocument(
            saved,
            vaultName: "Works",
            vaultRole: .draftProject
        )
        controller.installOpenedDocument(
            latestExternal,
            vaultName: "Works",
            vaultRole: .draftProject
        )

        #expect(session.editingSource == originalSource)
        #expect(session.editingRevision == original.fingerprint)

        // Model the exact save acknowledgement that precedes release of the
        // in-flight owner. The deferred workspace publication must then win.
        session.editingSource = savedSource
        session.originalEditingSource = savedSource
        session.editingRevision = saved.fingerprint
        session.isSavingEdit = false
        let conflict = controller.reconcileLatestDeferredWorkspaceSnapshot(
            for: session
        )

        #expect(conflict == nil)
        #expect(session.editingSource == latestExternalSource)
        #expect(session.originalEditingSource == latestExternalSource)
        #expect(session.editingRevision == latestExternal.fingerprint)
        #expect(session.conflict == nil)
    }

    @Test("Resolved rename updates each path projection without replacing sessions")
    func renamePreservesSessionIdentity() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let controller = DocumentController()
        let original = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Draft.md",
            source: "draft\n"
        )
        controller.installOpenedDocument(
            original,
            vaultName: "Works",
            vaultRole: .draftProject
        )
        let descriptor = try #require(controller.activeDocument)
        let session = controller.session(for: descriptor)
        session.preparePresentationMode(.source)

        controller.installOpenedDocument(
            note(
                vaultID: vaultID,
                noteID: noteID,
                path: "Chapters/Renamed Draft.md",
                source: "draft\n"
            ),
            vaultName: "Works",
            vaultRole: .draftProject
        )

        let renamed = try #require(controller.activeDocument)
        #expect(renamed.reference.relativePath == "Chapters/Renamed Draft.md")
        #expect(controller.session(for: renamed) === session)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == .livePreview)
    }

    @Test("Clean deleted documents close while dirty exact buffers remain recoverable")
    func deletedDocumentConvergence() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let original = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Deleted.md",
            source: "# Deleted\n\nOriginal.\n"
        )
        let removedWorkspace = workspace(vaultID: vaultID, notes: [])

        let cleanRead = DocumentController()
        cleanRead.installOpenedDocument(
            original,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus
        )
        let cleanReadDocument = try #require(cleanRead.selectedDocument)
        let cleanReadResult = cleanRead.receive(
            removedWorkspace,
            openDocuments: [cleanReadDocument]
        )
        #expect(cleanReadResult.removedDocuments == [cleanReadDocument])
        #expect(cleanReadResult.retainedDeletedDocuments.isEmpty)
        #expect(cleanRead.selectedDocument == nil)
        cleanRead.reconcileSessionLeases(
            leasedDocuments: [],
            selectedDocument: nil
        )
        #expect(cleanRead.closedPresentationCount == 0)

        let cleanEditor = DocumentController()
        cleanEditor.installOpenedDocument(
            original,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus
        )
        let cleanEditorDocument = try #require(cleanEditor.selectedDocument)
        let cleanEditorSession = cleanEditor.session(
            for: cleanEditorDocument.editingTarget
        )
        cleanEditor.beginEditing(
            session: cleanEditorSession,
            target: cleanEditorDocument.editingTarget,
            source: original.document.rawContent,
            revision: original.fingerprint,
            mode: .source
        )
        #expect(!cleanEditorSession.hasUnsavedChanges)
        let cleanEditorResult = cleanEditor.receive(
            removedWorkspace,
            openDocuments: [cleanEditorDocument]
        )
        #expect(cleanEditorResult.removedDocuments == [cleanEditorDocument])
        #expect(cleanEditorResult.retainedDeletedDocuments.isEmpty)
        #expect(cleanEditor.selectedDocument == nil)

        let dirtyEditor = DocumentController()
        dirtyEditor.installOpenedDocument(
            original,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus
        )
        let dirtyDocument = try #require(dirtyEditor.selectedDocument)
        let dirtySession = dirtyEditor.session(for: dirtyDocument.editingTarget)
        dirtyEditor.beginEditing(
            session: dirtySession,
            target: dirtyDocument.editingTarget,
            source: original.document.rawContent,
            revision: original.fingerprint,
            mode: .source
        )
        dirtySession.suppressAutosave = true
        let exactDirtyBuffer = "\u{FEFF}# Deleted\r\n\r\nUncommitted exact source.\r\n"
        dirtySession.editingSource = exactDirtyBuffer
        let dirtyResult = dirtyEditor.receive(
            removedWorkspace,
            openDocuments: [dirtyDocument]
        )
        #expect(dirtyResult.removedDocuments.isEmpty)
        #expect(dirtyResult.retainedDeletedDocuments == [dirtyDocument])
        #expect(dirtyEditor.selectedDocument == dirtyDocument)
        #expect(dirtyEditor.retainedDeletedDocumentPath == "Deleted.md")
        #expect(dirtySession.editingSource == exactDirtyBuffer)
        #expect(dirtySession.editError?.contains("deleted outside Scholium") == true)
    }

    @Test("A committed background source updates its clean detached editor without selecting it")
    func committedBackgroundSource() throws {
        let vault = UUID()
        let noteID = UUID()
        let original = note(vaultID: vault, noteID: noteID, path: "Source.md", source: "A claim.\n")
        let saved = note(vaultID: vault, noteID: noteID, path: "Source.md", source: "A claim. ^claim\n")
        let draft = note(vaultID: vault, noteID: UUID(), path: "Draft.md", source: "Draft.\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Topics", vaultRole: .topicKnowledge)
        let key = DocumentSessionKey(vaultID: vault, noteID: noteID)
        let session = controller.session(for: key)
        controller.beginEditing(
            session: session, target: .workspace(key), source: original.document.rawContent,
            revision: original.fingerprint, mode: .source)
        controller.installOpenedDocument(draft, vaultName: "Topics", vaultRole: .topicKnowledge)
        let selected = controller.selectedDocument
        #expect(session.isEditing && !session.editorSession.hasAttachedWebView)
        #expect(!session.hasUnsavedChanges)

        controller.recordCommittedSnapshot(saved, vaultName: "Topics", vaultRole: .topicKnowledge)

        #expect(controller.selectedDocument == selected)
        #expect(session.editingRevision == saved.fingerprint)
        #expect(session.editingSource == saved.document.rawContent)
        #expect(session.editorSession.checkedSource == saved.document.rawContent)
        #expect(!session.hasUnsavedChanges)

        session.suppressAutosave = true
        let newerDraft = "Researcher's newer draft.\n"
        #expect(
            session.editorSession.acceptEditorChanges(
                [
                    .init(
                        from: 0, to: EditorSourceOffsetMap(source: saved.document.rawContent).editorUTF16Length,
                        insert: newerDraft, exactInsert: newerDraft)
                ],
                baseGeneration: session.editorSession.generation,
                resultingGeneration: session.editorSession.generation + 1))
        let later = note(vaultID: vault, noteID: noteID, path: "Source.md", source: "External change.\n")
        controller.recordCommittedSnapshot(later, vaultName: "Topics", vaultRole: .topicKnowledge)
        #expect(session.editingSource == "Researcher's newer draft.\n")
        #expect(session.conflict != nil)
    }

    @Test("A detached Review session adopts external bytes before its editor is reconstructed", arguments: [false, true])
    func detachedReviewAdoptsExternalSource(normalizationOnly: Bool) throws {
        let vaultID = UUID()
        let noteID = UUID()
        let original = note(vaultID: vaultID, noteID: noteID, path: "Source.md", source: "\u{FEFF}Old café\r\n")
        let external = note(
            vaultID: vaultID, noteID: noteID, path: "Source.md",
            source: normalizationOnly ? "\u{FEFF}Old cafe\u{301}\r\n" : "\u{FEFF}External cafe\u{301} 🦉\r\n")
        let other = note(vaultID: vaultID, noteID: UUID(), path: "Other.md", source: "Other\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Topics", vaultRole: .topicKnowledge)
        let document = try #require(controller.selectedDocument)
        let session = controller.session(for: document.editingTarget)
        controller.beginEditing(
            session: session, target: document.editingTarget,
            source: original.document.rawContent, revision: original.fingerprint, mode: .source)
        session.editorSession.loadDocument(
            original.document.rawContent,
            documentID: session.editorSession.bridgeDocumentID, mode: .source)
        try controller.finishEditing(session: session, target: document.editingTarget)
        controller.installOpenedDocument(other, vaultName: "Topics", vaultRole: .topicKnowledge)
        let selected = controller.selectedDocument
        #expect(!session.isEditing && !session.editorSession.hasAttachedWebView && session.retainsEditorSurface)

        controller.recordCommittedSnapshot(external, vaultName: "Topics", vaultRole: .topicKnowledge)

        #expect(controller.selectedDocument == selected)
        #expect(session.editingRevision == external.fingerprint)
        let reconstructed = session.editorSession.sourceForViewAttachment(
            proposedSource: session.editingSource, documentID: session.editorSession.bridgeDocumentID)
        #expect(Data(reconstructed.utf8) == Data(external.document.rawContent.utf8))
        #expect(session.editorSession.startingFingerprint == external.fingerprint.sha256)
        #expect(!session.hasUnsavedChanges)
    }

    @Test("A detached conflict compares incremental editor input rather than the last lifecycle snapshot")
    func detachedConflictUsesCheckedSource() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let original = note(vaultID: vaultID, noteID: noteID, path: "Source.md", source: "Original\r\n")
        let external = note(vaultID: vaultID, noteID: noteID, path: "Source.md", source: "External\r\n")
        let other = note(vaultID: vaultID, noteID: UUID(), path: "Other.md", source: "Other\n")
        let controller = DocumentController()
        controller.installOpenedDocument(original, vaultName: "Topics", vaultRole: .topicKnowledge)
        let document = try #require(controller.selectedDocument)
        let session = controller.session(for: document.editingTarget)
        controller.beginEditing(
            session: session, target: document.editingTarget,
            source: original.document.rawContent, revision: original.fingerprint, mode: .source)
        session.editorSession.loadDocument(
            original.document.rawContent,
            documentID: session.editorSession.bridgeDocumentID, mode: .source)
        let insertion = "Researcher's cafe\u{301} 🦉\r\n"
        #expect(
            session.editorSession.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: insertion.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: insertion)],
                baseGeneration: 0, resultingGeneration: 1))
        #expect(session.editingSource == original.document.rawContent)
        #expect(session.hasUnsavedChanges && !session.editorSession.isLoaded)
        controller.installOpenedDocument(other, vaultName: "Topics", vaultRole: .topicKnowledge)

        controller.recordCommittedSnapshot(external, vaultName: "Topics", vaultRole: .topicKnowledge)

        let conflict = try #require(session.conflict)
        #expect(Data(conflict.editorSource.utf8) == Data((insertion + original.document.rawContent).utf8))
        #expect(Data(session.retainedExactSource.utf8) == Data(conflict.editorSource.utf8))
        #expect(session.editingRevision == original.fingerprint)
    }

    @Test("Joining a save retains its confirmed commit when editor acknowledgement fails", arguments: [false, true])
    func joinedSaveCommitReceipt(commitsBeforeFailure: Bool) async throws {
        let controller = DocumentController()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let session = controller.session(for: key)
        let saved = NoteDocument(relativePath: "Source.md", rawContent: "A claim. ^claim\n")
        let receipt = EditorSaveCommitReceipt()
        session.activeSaveCommitReceipt = receipt
        session.activeSaveTask = Task { @MainActor in
            if commitsBeforeFailure { receipt.document = saved }
            throw DocumentControllerError.editorUnavailable
        }
        defer { session.cancelScheduledWork() }
        var confirmed: [NoteDocument] = []

        await #expect(throws: DocumentControllerError.editorUnavailable) {
            try await controller.flushForExternalOperation(
                session: session, target: .workspace(key),
                onCommitted: { confirmed.append($0) })
        }

        #expect(confirmed.map(\.rawContent) == (commitsBeforeFailure ? [saved.rawContent] : []))
        #expect(session.editError != nil)
    }

    @Test("The note view delegates editor persistence and conflicts to one controller")
    func noteViewDelegatesEditorBehavior() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("@ObservedObject private var controller: DocumentController"))
        #expect(!source.contains("@ObservedObject var documentSession"))
        #expect(!source.contains("private func performEditingSave"))
        #expect(!source.contains("private func scheduleAutosave"))
        #expect(!source.contains("appState.saveSource"))
        #expect(!source.contains("appState.diskDocument"))
        #expect(!source.contains("appState.reloadDocumentFromDisk"))
    }

    @Test("Document entry views receive only DocumentController")
    func documentViewControllerBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let boundaries = [
            (
                name: "DocumentFeatureView",
                start: "struct DocumentFeatureView: View {",
                end: "private struct DocumentSessionFallback: View {"
            ),
            (
                name: "DocumentSessionFallback",
                start: "private struct DocumentSessionFallback: View {",
                end: "struct NoteContentView: View {"
            ),
            (
                name: "NoteContentView",
                start: "struct NoteContentView: View {",
                end: "// MARK: - Source comparison"
            ),
        ]

        for boundary in boundaries {
            let start = try #require(source.range(of: boundary.start))
            let end = try #require(
                source.range(
                    of: boundary.end,
                    range: start.upperBound..<source.endIndex
                ))
            let region = String(source[start.lowerBound..<end.lowerBound])

            #expect(
                region.contains("DocumentController"),
                Comment(rawValue: "\(boundary.name) must receive DocumentController")
            )
            #expect(
                !region.contains("ResearchController"),
                Comment(rawValue: "\(boundary.name) must not receive ResearchController")
            )
            #expect(
                !region.contains("researchController"),
                Comment(rawValue: "\(boundary.name) still stores or forwards a research controller")
            )
        }
    }

    private func note(
        vaultID: UUID,
        noteID: UUID,
        path: String,
        source: String
    ) -> WorkspaceNoteSnapshot {
        let document = NoteDocument(relativePath: path, rawContent: source)
        return WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            stableIdentity: .resolved(noteID),
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count,
                creationDate: nil,
                modificationDate: nil
            ),
            graphCounts: WorkspaceGraphCounts(
                incoming: 0,
                outgoing: 0,
                broken: 0,
                ambiguous: 0
            )
        )
    }

    private func workspace(
        vaultID: UUID,
        notes: [WorkspaceNoteSnapshot]
    ) -> WorkspaceSnapshot {
        let vault = RegisteredVault(
            id: vaultID,
            name: "Analyses",
            role: .sourceCorpus,
            canonicalPath: "/fixtures/Analyses"
        )
        let triptych = ScholiumTriptych(
            name: "Document Convergence",
            paperAnalysisVaultID: vaultID,
            topicKnowledgeVaultID: UUID(),
            outputVaultID: UUID()
        )
        let documents = notes.map(\.document)
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: [vault],
            documents: [vaultID: documents]
        )
        return WorkspaceSnapshot(
            triptych: triptych,
            mode: .live,
            generatedAt: Date(),
            vaults: [
                WorkspaceVaultSnapshot(
                    slot: .paperAnalysis,
                    vault: vault,
                    pathComparisonPolicy: VaultPathComparisonPolicy(
                        caseSensitive: true,
                        normalizationSensitive: true
                    ),
                    documents: notes,
                    identityRecovery: NoteIdentityRecoveryState(
                        identities: [:],
                        ambiguities: [],
                        pendingRebindings: [],
                        failures: []
                    )
                )
            ],
            discovery: WorkspaceDiscoverySnapshot(
                catalog: catalog,
                searchGeneration: SearchGenerationID(
                    triptychID: triptych.id,
                    sequence: 1,
                    sourceManifestHash: "document-convergence"
                )
            ),
            research: WorkspaceResearchSnapshot(
                healthIssues: []
            )
        )
    }
}
