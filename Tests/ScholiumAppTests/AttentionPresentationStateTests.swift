import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Attention presentation state")
@MainActor
struct AttentionPresentationStateTests {
    @Test("Sidebar Attention projects exact counts without toolbar routing state")
    func scopeCountProjection() {
        let counts = AttentionScopeCounts(values: [
            .paperAnalysis: 2,
            .topicKnowledge: 0,
            .output: 1,
        ])

        #expect(counts.count(for: .paperAnalysis) == 2)
        #expect(counts.count(for: .topicKnowledge) == 0)
        #expect(counts.count(for: .output) == 1)
        #expect(AttentionScopeCounts(values: [:]).count(for: .paperAnalysis) == 0)
    }

    @Test("The three visual groups cover each existing derived kind exactly once")
    func groupsAreCompleteAndExclusive() {
        let grouped = AttentionIssueGroup.allCases.flatMap(\.kinds)

        #expect(grouped.count == AttentionQueueKind.allCases.count)
        #expect(Set(grouped) == Set(AttentionQueueKind.allCases))
        #expect(Set(AttentionIssueGroup.identityAndMetadata.kinds) == Set([
            .changeAttributionNeeded, .malformedMetadata, .unresolvedIdentity,
        ]))
        #expect(Set(AttentionIssueGroup.structureAndConnections.kinds) == Set([
            .possibleOrphan, .brokenConnection, .ambiguousConnection,
        ]))
        #expect(Set(AttentionIssueGroup.revisionAndReliance.kinds) == Set([
            .changedSinceSettled, .materialChangedSinceUse,
        ]))
    }

    @Test("Sidebar Scope changes clear an Inspector-applied This Note subset")
    func scopeChangeClearsNoteSubset() {
        let state = AttentionPresentationState()
        let note = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Topic.md")

        state.present(workspaceSlot: .topicKnowledge, noteScope: note)
        #expect(state.noteScope == note)
        state.selectWorkspaceSlot(.output)

        #expect(state.workspaceSlot == .output)
        #expect(state.noteScope == nil)
        #expect(state.selectedItemID == nil)
    }

    @Test("A Workspace-window switch resets transient filtering and selection")
    func workspaceSwitchResetsTransientState() {
        let state = AttentionPresentationState()
        let note = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Topic.md")
        state.present(workspaceSlot: .topicKnowledge, noteScope: note)
        state.filter.query = "orphan"
        state.filter.kind = .possibleOrphan
        state.select("task-1")

        state.resetForWorkspaceSwitch()

        #expect(state.filter.query.isEmpty)
        #expect(state.filter.kind == nil)
        #expect(state.selectedItemID == nil)
        #expect(state.noteScope == nil)
        #expect(state.workspaceSlot == .topicKnowledge)
    }

    @Test("Removed tasks select next, then previous, then the filter control")
    func removalFocusOrder() {
        let state = AttentionPresentationState()
        state.reconcileVisibleItems(["a", "b", "c"])
        state.select("b")

        state.reconcileVisibleItems(["a", "c"])
        #expect(state.selectedItemID == "c")

        state.reconcileVisibleItems(["a"])
        #expect(state.selectedItemID == "a")

        let focusGeneration = state.filterFocusRequestGeneration
        state.reconcileVisibleItems([])
        #expect(state.selectedItemID == nil)
        #expect(state.filterFocusRequestGeneration == focusGeneration + 1)
    }
}
