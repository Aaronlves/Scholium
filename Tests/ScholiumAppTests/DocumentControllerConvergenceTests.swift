import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Document controller convergence")
@MainActor
struct DocumentControllerConvergenceTests {
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
            vaultRole: .draftProject,
            inNewTab: false
        )
        clean.installOpenedDocument(
            original,
            vaultName: "Works",
            vaultRole: .draftProject,
            inNewTab: false
        )

        let key = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        let exactDirtyBuffer = "\u{FEFF}# Argument\r\n\r\nUncommitted local thought.\r\n"
        dirty.session(for: try #require(dirty.activeDocument)).editingSource = exactDirtyBuffer

        dirty.installOpenedDocument(
            external,
            vaultName: "Works",
            vaultRole: .draftProject,
            inNewTab: false
        )
        clean.installOpenedDocument(
            external,
            vaultName: "Works",
            vaultRole: .draftProject,
            inNewTab: false
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
            vaultRole: .draftProject,
            inNewTab: false
        )
        let descriptor = try #require(controller.activeDocument)
        let session = controller.session(for: descriptor)
        session.presentationMode = .source

        controller.installOpenedDocument(
            note(
                vaultID: vaultID,
                noteID: noteID,
                path: "Chapters/Renamed Draft.md",
                source: "draft\n"
            ),
            vaultName: "Works",
            vaultRole: .draftProject,
            inNewTab: false
        )

        let renamed = try #require(controller.activeDocument)
        #expect(renamed.reference.relativePath == "Chapters/Renamed Draft.md")
        #expect(controller.session(for: renamed) === session)
        #expect(session.presentationMode == .source)
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
                name: "NoteTabView",
                start: "struct NoteTabView: View {",
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
                end: "private enum DocumentTabStatus: Equatable {"
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
            lifecycle: .active,
            review: nil,
            graphCounts: WorkspaceGraphCounts(
                incoming: 0,
                outgoing: 0,
                broken: 0,
                ambiguous: 0
            )
        )
    }
}
