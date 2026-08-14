import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Document controller convergence")
@MainActor
struct DocumentControllerConvergenceTests {
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
        controller.pendingSourceLine = 99

        controller.installOpenedDocument(
            created,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            managedCreationBodyStartUTF16: created.document.bodyUTF16Offset
        )

        let session = try #require(controller.retainedSession(for: .init(
            vaultID: vaultID,
            noteID: noteID
        )))
        #expect(controller.currentPresentationMode == .livePreview)
        #expect(controller.requestedPresentationMode == nil)
        #expect(controller.pendingSourceLine == nil)
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

    @Test("Read-only lifecycle Notes retain workspace Edit intent but present Review")
    func readOnlyNotePresentsReview() throws {
        let vaultID = UUID()
        let noteID = UUID()
        let controller = DocumentController()
        let archived = note(
            vaultID: vaultID,
            noteID: noteID,
            path: "Set Aside/Archived.md",
            source: "# Archived\n",
            lifecycle: .setAside
        )

        controller.installOpenedDocument(
            archived,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus
        )

        let session = try #require(controller.retainedSession(for: .init(
            vaultID: vaultID,
            noteID: noteID
        )))
        #expect(controller.currentPresentationMode == .livePreview)
        #expect(controller.chromeProjection.mode == .read)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == nil)
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
        let session = try #require(controller.retainedSession(for: .init(
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
                end: "struct ResearchInspectorView: View {"
            ),
            (
                name: "NoteContentView",
                start: "struct NoteContentView: View {",
                end: "// MARK: - Research Record"
            ),
        ]

        for boundary in boundaries {
            let start = try #require(source.range(of: boundary.start))
            let end = try #require(source.range(
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
        source: String,
        lifecycle: WorkspaceDocumentLifecycle = .active
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
            lifecycle: lifecycle,
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
            vaults: [WorkspaceVaultSnapshot(
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
            )],
            discovery: WorkspaceDiscoverySnapshot(
                catalog: catalog,
                searchGeneration: SearchGenerationID(
                    triptychID: triptych.id,
                    sequence: 1,
                    sourceManifestHash: "document-convergence"
                )
            ),
            research: WorkspaceResearchSnapshot(
                critiques: [],
                checkpointListing: TriptychCheckpointListing(
                    checkpoints: [],
                    unreadableEntries: []
                ),
                healthIssues: []
            )
        )
    }
}
