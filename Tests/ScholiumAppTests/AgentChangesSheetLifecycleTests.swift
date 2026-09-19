import AppKit
import Observation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Agent Changes sheet lifecycle", .serialized)
@MainActor
struct AgentChangesSheetLifecycleTests {
    // Needs a document window and sheet at a workable size.
    @Test("Loading, displaying, and dismissing a real sheet preserve the document window frame", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence))
    func parentFrameSurvivesPresentation() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        // This fixture deliberately leaves room for the sheet. Screen-edge
        // accommodation is native behavior, not the invariant under test.
        try #require(visible.width >= 800 && visible.height >= 680)
        let suite = "Scholium-SheetLifecycle-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = SheetLifecycleState()
        let change = AgentChange(
            id: UUID(), triptychID: UUID(), operation: .create, noteID: UUID(), role: .topicKnowledge,
            originalRelativePath: nil, finalRelativePath: "Synthetic Created Note.md", beforeFingerprint: nil,
            afterFingerprint: DocumentFingerprint(content: "Synthetic current content."), state: .confirmed,
            createdAt: Date(), confirmedAt: Date(), undoneAt: nil)
        let host = NSHostingView(rootView: SheetLifecycleHost(state: state, change: change, defaults: defaults))
        host.sizingOptions = []
        let size = NSSize(width: min(1000, visible.width - 40), height: min(740, visible.height - 80))
        let parent = NSWindow(
            contentRect: NSRect(
                x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40,
                width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        parent.title = "Scholium synthetic sheet lifecycle test"
        parent.isReleasedWhenClosed = false
        parent.contentView = host
        defer {
            state.reviewContinuation?.resume()
            state.reviewContinuation = nil
            state.isPresented = false
            if let sheet = parent.attachedSheet {
                parent.endSheet(sheet)
                sheet.orderOut(nil)
            }
            parent.orderOut(nil)
            parent.contentView = nil
            parent.close()
            defaults.removePersistentDomain(forName: suite)
        }
        parent.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await wait { parent.isVisible && host.window === parent }
        let initialFrame = parent.frame

        state.isPresented = true
        try await wait { parent.attachedSheet?.isVisible == true && state.reviewContinuation != nil }
        let sheet = try #require(parent.attachedSheet)
        #expect(parent.frame == initialFrame, "Opening the loading sheet moved the document window")

        state.reviewContinuation?.resume()
        state.reviewContinuation = nil
        try await wait {
            AgentChangeViewedLedger(data: defaults.data(forKey: AgentChangeViewedLedger.key) ?? Data())
                .ids.contains(change.id)
        }
        #expect(parent.attachedSheet === sheet, "Loading the detail must retain the presented sheet")
        #expect(parent.frame == initialFrame, "Displaying the detail moved the document window")

        state.isPresented = false
        try await wait { state.didDismiss && parent.attachedSheet == nil && !sheet.isVisible && sheet.sheetParent == nil }
        #expect(parent.frame == initialFrame, "Dismissing the sheet moved the document window")
    }

    private func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !ready(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(ready(), "The native sheet lifecycle did not reach the expected state")
    }
}

@MainActor
@Observable
private final class SheetLifecycleState {
    var isPresented = false
    var didDismiss = false
    @ObservationIgnored var reviewContinuation: CheckedContinuation<Void, Never>?
}

@MainActor
private struct SheetLifecycleHost: View {
    @Bindable var state: SheetLifecycleState
    let change: AgentChange
    let defaults: UserDefaults

    var body: some View {
        Text("Disposable document window")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $state.isPresented, onDismiss: { state.didDismiss = true }) {
                AgentChangesView(
                    scope: .exact(change.id), load: { [change] },
                    loadReview: { _ in
                        await withCheckedContinuation { state.reviewContinuation = $0 }
                        return AgentChangeReview(
                            change: change, comparison: nil, currentCreatedSource: "Synthetic current content.",
                            endingRevisionState: .current)
                    },
                    undo: { _ in Issue.record("A sheet lifecycle test must not undo a change") }
                )
                .defaultAppStorage(defaults)
            }
    }
}
