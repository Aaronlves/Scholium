import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Managed Note creation navigation currency", .serialized) @MainActor
struct WindowManagedNoteCurrencyTests {
    @Test(
        "Superseded creation publication reports only genuine committed-outcome warnings",
        arguments: [false, true])
    func supersededPublicationDoesNotReportPresentationFailure(hasDerivedWarning: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let window = fixture.window
            let origin = try #require(window.documentController.selectedDocument)
            let originReference = try #require(origin.workspaceDescriptor?.reference)
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            let vault = try #require(window.currentRegisteredVault)
            let createdOutcome = try await capabilities.libraryMutations.createUntitledNote(inVault: vault.id, folderRelativePath: nil)
            try #require(createdOutcome.derivedRefreshWarning == nil)
            try #require(createdOutcome.identityRecoveryWarning == nil)
            let created = createdOutcome.committedValue
            let createdKey = DocumentSessionKey(vaultID: created.id.vaultID, noteID: try #require(created.stableIdentity.resolvedID))
            let derivedWarning = "Synthetic committed creation derived-refresh warning."
            let outcome =
                hasDerivedWarning
                ? WorkspaceMutationOutcome(committedValue: created, derivedRefreshWarning: derivedWarning)
                : createdOutcome
            let initialIssueCount = window.shellState.operationIssues.count
            var requestedNewerNavigation = false
            var selectedAtPublicationExit: WindowSelectedDocument?
            window.enqueueCurrencyAwareDocumentTransition(preservingCurrentEditorState: false) { isCurrent in
                await window.publishCommittedNoteCreation(
                    outcome,
                    isCurrent: {
                        let wasCurrent = isCurrent()
                        #expect(wasCurrent)
                        requestedNewerNavigation = true
                        window.enqueueDocumentTransition(preparation: window.openingPreparation(for: originReference)) {
                            try await window.activateWorkspaceReference(originReference, tabActivation: .place(.replaceSelected))
                        }
                        #expect(!isCurrent())
                        // Publication passes its early guard; activation must use
                        // the coordinator's actual currency after this request.
                        return wasCurrent
                    })
                selectedAtPublicationExit = window.documentController.selectedDocument
            } didFail: { error in
                Issue.record("The committed publication could not complete: \(error)")
            }
            await window.waitForDocumentTransitions()

            #expect(requestedNewerNavigation)
            #expect(selectedAtPublicationExit == origin)
            #expect(window.documentController.selectedDocument == origin)
            #expect(window.documentTabController.selectedTab?.document == origin)
            #expect(!window.documentTabController.tabs.contains { $0.document.sessionKey == createdKey })
            #expect(window.shellState.operationIssues.count == initialIssueCount + (hasDerivedWarning ? 1 : 0))
            if hasDerivedWarning {
                let issue = try #require(window.shellState.operationIssues.last)
                #expect(issue.kind == .warning)
                #expect(issue.offersRefresh)
                #expect(issue.detail?.hasSuffix(derivedWarning) == true)
            }
            let listed = try #require(window.notes.first { $0.summary.id == created.id })
            #expect(listed.summary.stableIdentity.resolvedID == createdKey.noteID)
            #expect(listed.relativePath.utf8.elementsEqual(created.id.relativePath.utf8))
            #expect(listed.summary.fingerprint == created.document.fingerprint)
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent(created.id.relativePath)) == created.document.sourceBytes)
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(Fixture.originSource.utf8))
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.window.waitForDocumentTransitions()
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("A newer opening request cancels creation activation without losing its committed source or Library entry")
    func newerRequestWinsDuringCreationActivation() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let window = fixture.window
            let origin = try #require(window.documentController.selectedDocument)
            let originReference = try #require(origin.workspaceDescriptor?.reference)
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            let vault = try #require(window.currentRegisteredVault)
            let outcome = try await capabilities.libraryMutations.createUntitledNote(inVault: vault.id, folderRelativePath: nil)
            let created = outcome.committedValue
            let noteID = try #require(created.stableIdentity.resolvedID)
            let createdKey = DocumentSessionKey(vaultID: created.id.vaultID, noteID: noteID)
            _ = try #require(
                window.workspaceProjectionController.recordCommittedNoteCreation(
                    created, visibleVaultID: vault.id, visibleSourceScope: window.noteSourceScope))
            let reference = VaultNoteReference(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                relativePath: created.id.relativePath, stableNoteID: noteID.uuidString)
            var reachedSourceValidation = false
            var cancelledActivation = false
            var selectedAtActivationExit: WindowSelectedDocument?
            window.enqueueCurrencyAwareDocumentTransition(preservingCurrentEditorState: false) { isCurrent in
                defer { selectedAtActivationExit = window.documentController.selectedDocument }
                do {
                    try await window.activateWorkspaceReference(
                        reference, tabActivation: .place(.replaceSelected),
                        managedCreationBodyStartUTF16: created.document.bodyUTF16Offset,
                        committedSnapshot: created.sourceAheadSnapshot,
                        validateSource: {
                            reachedSourceValidation = true
                            window.enqueueDocumentTransition(preparation: window.openingPreparation(for: originReference)) {
                                try await window.activateWorkspaceReference(originReference, tabActivation: .place(.replaceSelected))
                            }
                            #expect(!isCurrent())
                        })
                    Issue.record("The superseded creation activation still replaced the selected Document.")
                } catch is CancellationError {
                    cancelledActivation = true
                    throw CancellationError()
                }
            } didFail: { error in
                if !(error is CancellationError) {
                    Issue.record("Creation activation failed before its currency check: \(error)")
                }
            }
            await window.waitForDocumentTransitions()
            #expect(reachedSourceValidation)
            #expect(cancelledActivation)
            #expect(selectedAtActivationExit == origin)
            #expect(window.documentController.selectedDocument == origin)
            #expect(window.documentTabController.selectedTab?.document == origin)
            #expect(!window.documentTabController.tabs.contains { $0.document.sessionKey == createdKey })
            let listed = try #require(window.notes.first { $0.summary.id == created.id })
            #expect(listed.summary.stableIdentity.resolvedID == noteID)
            #expect(listed.relativePath.utf8.elementsEqual(created.id.relativePath.utf8))
            #expect(listed.summary.fingerprint == created.document.fingerprint)
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent(created.id.relativePath)) == created.document.sourceBytes)
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(Fixture.originSource.utf8))
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.window.waitForDocumentTransitions()
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @MainActor
    private struct Fixture {
        static let originSource = "\u{FEFF}Origin source 中文 😀 e\u{301}。\r\n"
        let root: URL
        let works: URL
        let store: WorkspaceStore
        let window: WindowModel

        static func make() async throws -> Self {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/managed-note-currency/\(UUID())", isDirectory: true)
            let triptych = root.appendingPathComponent("Triptych", isDirectory: true)
            let analyses = triptych.appendingPathComponent("Analyses", isDirectory: true)
            let topics = triptych.appendingPathComponent("Topics", isDirectory: true)
            let works = triptych.appendingPathComponent("Works", isDirectory: true)
            for directory in [analyses, topics, works] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data(originSource.utf8).write(to: works.appendingPathComponent("Origin.md"))
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
            do {
                let configured = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Creation currency fixture")
                let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
                await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
                try await window.openWorkspaceVault(.output)
                window.documentController.rememberPresentationMode(.read)
                try await window.openNote("Origin.md")
                return Self(root: root, works: works, store: store, window: window)
            } catch {
                await store.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }
}
