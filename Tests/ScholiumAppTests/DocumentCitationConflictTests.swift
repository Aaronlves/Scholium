import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Document citation conflicts")
@MainActor
struct DocumentCitationConflictTests {
    enum ReloadInterleaving: CaseIterable {
        case unchanged, newerPeerCompanion, localMetadataAfterRead
    }

    @Test("Metadata-only conflict reload keeps the compared pair and concurrent edits distinct", arguments: ReloadInterleaving.allCases)
    func metadataOnlyConflictReload(interleaving: ReloadInterleaving) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/citation-conflict-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let source = "# Synthetic citation state\r\n"
        let file = vaults[1].appendingPathComponent("Citation.md")
        try Data(source.utf8).write(to: file)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Citation conflict fixture")
            let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
            let summary = try #require(vault.documents.first { $0.id.relativePath == "Citation.md" })
            let hydrated = try await capabilities.documents.hydrate(summary)
            let noteID = try #require(hydrated.stableIdentity.resolvedID)
            let target = NoteMutationTarget(documentID: summary.id, stableNoteID: noteID, revision: hydrated.fingerprint)
            let baseData = ZoteroCitationData(documentData: "synthetic baseline preferences")
            let diskData = ZoteroCitationData(documentData: "synthetic compared preferences")
            let localData = ZoteroCitationData(documentData: "synthetic unsaved preferences")
            let newerData = ZoteroCitationData(documentData: "synthetic newer preferences")
            let baseDocument = try await capabilities.documents.save(
                target, changeSet: .citationSource(source, .init(expectedRevision: nil, data: baseData))
            ).committedValue.document
            let base = try #require(baseDocument.citationSnapshot)
            let diskDocument = try await capabilities.documents.save(
                target, changeSet: .citationSource(source, .init(expectedRevision: base.revision, data: diskData))
            ).committedValue.document
            let compared = try #require(diskDocument.citationSnapshot)
            let controller = DocumentController()
            controller.installOpenedDocument(
                WorkspaceNoteSnapshot(summary: hydrated.summary, document: baseDocument),
                vaultName: "Topics", vaultRole: .topicKnowledge)
            let descriptor = try #require(controller.activeDocument)
            let editingTarget = DocumentEditingTarget.workspace(descriptor.sessionKey)
            let session = controller.session(for: descriptor)
            defer {
                session.cancelScheduledWork()
                controller.unbind()
            }
            controller.beginEditing(
                session: session, target: editingTarget, source: source,
                revision: hydrated.fingerprint, mode: .source)
            session.editorSession.loadDocument(
                source, documentID: session.editorSession.bridgeDocumentID,
                mode: .source, citationSnapshot: base)
            #expect(
                session.editorSession.acceptEditorChanges(
                    [], baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: localData))
            session.conflict = DocumentConflictSnapshot(
                relativePath: "Citation.md", editorSource: source, diskSource: source,
                baseRevision: hydrated.fingerprint, baseCitationSnapshot: base,
                editorCitationData: localData, diskCitationSnapshot: compared)
            session.presentConflictComparison()
            #expect(session.conflictComparison?.hasCitationConflict == true)
            #expect(session.conflictComparison?.editorRevision == session.conflictComparison?.diskRevision)

            var latestDisk = compared
            if interleaving == .newerPeerCompanion {
                let advanced = try await capabilities.documents.save(
                    target, changeSet: .citationSource(source, .init(expectedRevision: compared.revision, data: newerData))
                ).committedValue.document
                latestDisk = try #require(advanced.citationSnapshot)
                #expect(latestDisk.revision != compared.revision)
            }
            controller.bind(
                to: capabilities.documents,
                documentDidCommit: { _ in
                    if interleaving == .localMetadataAfterRead {
                        #expect(
                            session.editorSession.acceptEditorChanges(
                                [], baseGeneration: 1, resultingGeneration: 2, citationManaged: true, citationData: newerData))
                    }
                })
            if interleaving == .unchanged {
                try await controller.reloadFromDisk(session: session, target: editingTarget)
                #expect(session.conflict == nil)
                #expect(!session.isEditing && !session.hasUnsavedChanges)
                #expect(session.editorSession.committedCitationSnapshot == compared)
                #expect(session.editorSession.checkedCitationData == diskData)
            } else {
                do {
                    try await controller.reloadFromDisk(session: session, target: editingTarget)
                    Issue.record("Reload discarded a metadata-only change outside the compared pair")
                } catch {
                    #expect(session.conflict != nil)
                    #expect(session.isEditing && session.hasUnsavedChanges)
                }
                #expect(session.editorSession.committedCitationSnapshot == base)
                #expect(session.editorSession.checkedCitationData == (interleaving == .localMetadataAfterRead ? newerData : localData))
            }
            #expect(Data(session.editorSession.checkedSource.utf8) == Data(source.utf8))
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            #expect(try await capabilities.documents.load(summary.id).citationSnapshot == latestDisk)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}
