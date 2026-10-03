import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Window document opening preparation", .serialized)
@MainActor
struct WindowDocumentOpeningPreparationTests {
    private enum FixtureFailure: Error { case save }

    @Test("Replacement guards its outgoing source without joining an unrelated retained save", arguments: [false, true])
    func replacementSaveIsTargetLocal(failsOutgoing: Bool) async throws {
        let (model, background, outgoing) = makeModel()
        let failing = failsOutgoing ? outgoing : background
        failing.beginEditing(in: .source)
        failing.originalEditingSource = "Saved\r\n"
        let exactDraft = "\u{FEFF}Unsaved 中文 😀 e\u{301}。\r\n"
        failing.editingSource = exactDraft
        failing.suppressAutosave = true
        let save = Task<EditorSaveOutcome, Error> { throw FixtureFailure.save }
        failing.activeSaveTask = save
        defer {
            save.cancel()
            failing.activeSaveTask = nil
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        let selectedAtStart = model.documentController.selectedDocument
        var reachedDestination = false
        model.enqueueDocumentTransition {
            reachedDestination = true
        }
        await model.waitForDocumentTransitions()
        #expect(reachedDestination == !failsOutgoing)
        #expect(model.documentController.selectedDocument == selectedAtStart)
        #expect(Data(failing.editingSource.utf8) == Data(exactDraft.utf8))
        #expect(model.documentTabController.tabs.count == 2)
    }

    @Test("Opening a new or retained tab preserves the outgoing dirty session without saving", arguments: [DocumentTabPlacement.newTab, .replaceSelected])
    func retainedOpeningDoesNotSaveOutgoing(placement: DocumentTabPlacement) async throws {
        let (model, background, outgoing) = makeModel()
        let reference = try #require(model.documentTabController.tabs.first?.document.workspaceDescriptor?.reference)
        outgoing.beginEditing(in: .source)
        outgoing.originalEditingSource = "Saved\r\n"
        let draft = "\u{FEFF}Uncommitted 中文 😀。\r\n"
        outgoing.editingSource = draft
        outgoing.editError = "Retained failure"
        outgoing.canRetrySave = true
        outgoing.suppressAutosave = true
        outgoing.scrollFraction = 0.62
        defer {
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var reachedDestination = false
        model.enqueueDocumentTransition(preparation: model.openingPreparation(for: reference, placement: placement)) {
            reachedDestination = true
        }
        await model.waitForDocumentTransitions()
        #expect(reachedDestination)
        #expect(Data(outgoing.editingSource.utf8) == Data(draft.utf8))
        #expect(outgoing.hasUnsavedChanges)
        #expect(outgoing.editError == "Retained failure")
        #expect(outgoing.scrollFraction == 0.62)
        #expect(outgoing.activeSaveTask == nil)
    }

    @Test("A destination removed before queued opening preparation requires an outgoing save")
    func queuedDestinationLossRequiresSave() async throws {
        let (model, background, outgoing) = makeModel()
        let tab = try #require(model.documentTabController.tabs.first)
        let reference = try #require(tab.document.workspaceDescriptor?.reference)
        let save = installFailedSave(on: outgoing)
        var release: CheckedContinuation<Void, Never>?
        defer {
            release?.resume()
            save.cancel()
            outgoing.activeSaveTask = nil
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        model.documentTransitionCoordinator.enqueueCleanup { _ in
            await withCheckedContinuation { release = $0 }
            model.documentTabController.removeTabs(withIDs: [tab.id])
        }
        try await waitUntil { release != nil }
        var reachedDestination = false
        model.enqueueDocumentTransition(preparation: model.openingPreparation(for: reference)) {
            reachedDestination = true
        }
        release?.resume()
        release = nil
        await model.waitForDocumentTransitions()
        #expect(!reachedDestination)
        #expect(model.documentController.selectedDocument == model.documentTabController.selectedTab?.document)
        #expect(outgoing.hasUnsavedChanges)
    }

    @Test("A retained destination lost during preparation leaves its outgoing dirty session open")
    func destinationLossDuringPreparationPreservesOrigin() async throws {
        let (model, background, outgoing) = makeModel()
        let tab = try #require(model.documentTabController.tabs.first)
        let reference = try #require(tab.document.workspaceDescriptor?.reference)
        outgoing.beginEditing(in: .source)
        outgoing.originalEditingSource = "Saved\r\n"
        outgoing.editingSource = "Unsaved 中文 😀。\r\n"
        outgoing.suppressAutosave = true
        var release: CheckedContinuation<Void, Never>?
        let inFlight = Task<EditorSaveOutcome, Error> {
            await withCheckedContinuation { release = $0 }
            return .clean
        }
        outgoing.activeSaveTask = inFlight
        var failedSave: Task<EditorSaveOutcome, Error>?
        defer {
            release?.resume()
            inFlight.cancel()
            failedSave?.cancel()
            outgoing.activeSaveTask = nil
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var reachedDestination = false
        var beganPreparation = false
        model.enqueueDocumentTransition(
            preparation: .openingDocument(
                placement: .replaceSelected,
                retainedTab: {
                    beganPreparation = true
                    return model.documentTabController.tab(for: reference)
                })
        ) {
            reachedDestination = true
        }
        try await waitUntil { release != nil && beganPreparation }
        model.documentTabController.removeTabs(withIDs: [tab.id])
        failedSave = installFailedSave(on: outgoing)
        release?.resume()
        release = nil
        await model.waitForDocumentTransitions()
        #expect(!reachedDestination)
        #expect(outgoing.hasUnsavedChanges)
        #expect(model.documentController.selectedDocument == model.documentTabController.selectedTab?.document)
    }

    private func installFailedSave(on session: DocumentSessionModel) -> Task<EditorSaveOutcome, Error> {
        session.beginEditing(in: .source)
        session.originalEditingSource = "Saved\r\n"
        session.editingSource = "\u{FEFF}Unsaved 中文 😀 e\u{301}。\r\n"
        session.suppressAutosave = true
        let save = Task<EditorSaveOutcome, Error> { throw FixtureFailure.save }
        session.activeSaveTask = save
        return save
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw FixtureFailure.save }
            await Task.yield()
        }
    }

    @Test(
        "Synthetic replacement records the delay contributed by an unrelated pending save",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_TAB_BACKGROUND_SAVE_MEASURE"] == "1")
    )
    func syntheticBackgroundSaveDepartureMeasurement() async throws {
        // This is a controlled causal probe: the background save task is a
        // substituted 250 ms boundary. No disk or user-visible paint claim.
        let (model, background, outgoing) = makeModel()
        background.beginEditing(in: .source)
        background.originalEditingSource = "Saved\r\n"
        let exactDraft = "\u{FEFF}Unsaved 中文 😀 e\u{301}。\r\n"
        background.editingSource = exactDraft
        background.suppressAutosave = true
        defer {
            background.activeSaveTask?.cancel()
            background.activeSaveTask = nil
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var milliseconds: [Double] = []
        for sample in 0..<7 {
            let pending = Task<EditorSaveOutcome, Error> { @MainActor in
                try await Task.sleep(for: .milliseconds(250))
                return .clean
            }
            background.activeSaveTask = pending
            let start = ContinuousClock.now
            var elapsed: Duration?
            model.enqueueDocumentTransition {
                elapsed = start.duration(to: .now)
            }
            await model.waitForDocumentTransitions()
            let duration = try #require(elapsed).components
            if sample >= 2 {
                milliseconds.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            }
            _ = try await pending.value
            background.activeSaveTask = nil
            #expect(Data(background.editingSource.utf8) == Data(exactDraft.utf8))
        }
        print(
            "TAB_BACKGROUND_SAVE_SCENARIO substituted_save_ms=250 warmups=2 retained=5 "
                + "milliseconds=\(milliseconds.map { String(format: "%.3f", $0) }.joined(separator: ","))")
        #expect(milliseconds.count == 5)
    }

    private func makeModel() -> (WindowModel, DocumentSessionModel, DocumentSessionModel) {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let vaultID = UUID()
        var sessions: [DocumentSessionModel] = []
        for path in ["Background.md", "Outgoing.md"] {
            let noteID = UUID()
            let snapshot = WorkspaceNoteSnapshot(
                id: .init(vaultID: vaultID, relativePath: path), vaultRole: .topicKnowledge,
                stableIdentity: .resolved(noteID),
                document: .init(relativePath: path, rawContent: "Saved\r\n"),
                fileMetadata: .init(byteCount: 7, creationDate: nil, modificationDate: nil),
                graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
            model.documentController.installOpenedDocument(snapshot, vaultName: "Fixture", vaultRole: .topicKnowledge)
            let document = model.documentController.selectedDocument!
            let session = model.documentController.session(for: document.editingTarget)
            session.finishEditing()
            sessions.append(session)
            model.documentTabController.activate(document: document, title: path, toolTip: path, placement: .newTab)
        }
        model.reconcileDocumentSessionLeases()
        return (model, sessions[0], sessions[1])
    }
}
