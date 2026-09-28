import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Attention presentation state")
@MainActor
struct AttentionPresentationStateTests {
    @Test("Workspace Note totals preserve zero and distinguish unavailable")
    func workspaceNoteCountProjection() {
        let counts = SidebarWorkspaceNoteCounts(values: [
            .paperAnalysis: 12,
            .topicKnowledge: 0,
        ])

        #expect(counts.count(for: .paperAnalysis) == 12)
        #expect(counts.count(for: .topicKnowledge) == 0)
        #expect(counts.count(for: .output) == nil)
    }

    @Test("Workspace changes clear an Inspector-applied This Note subset")
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

    @Test("Notification filters expose one complete or one type-specific queue")
    func notificationFilterOwnership() {
        #expect(AttentionNotificationFilter.all.showsChanges)
        #expect(AttentionNotificationFilter.all.showsSettlements)

        #expect(AttentionNotificationFilter.changes.showsChanges)
        #expect(!AttentionNotificationFilter.changes.showsSettlements)

        #expect(!AttentionNotificationFilter.settlements.showsChanges)
        #expect(AttentionNotificationFilter.settlements.showsSettlements)
    }

    @Test("Triptych Attention remains aggregate across workspace changes")
    func triptychScopeDoesNotRetarget() {
        let state = AttentionPresentationState()

        state.present(workspaceSlot: nil, noteScope: nil)
        state.selectWorkspaceSlot(.output)

        #expect(state.workspaceSlot == nil)
        #expect(state.noteScope == nil)
    }

    @Test("A Workspace-window switch resets transient filtering and selection")
    func workspaceSwitchResetsTransientState() {
        let state = AttentionPresentationState()
        let note = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Topic.md")
        state.present(workspaceSlot: .topicKnowledge, noteScope: note)
        state.filter.query = "orphan"
        state.notificationFilter = .changes
        state.select("task-1")

        state.resetForWorkspaceSwitch()

        #expect(state.filter.query.isEmpty)
        #expect(state.notificationFilter == .all)
        #expect(state.selectedItemID == nil)
        #expect(state.noteScope == nil)
        #expect(state.workspaceSlot == .topicKnowledge)
    }

    @Test("Notification empty and refresh state copy resolves in the interface locale")
    func localizedNotificationStateCopy() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(
            AttentionNotificationCopy.refreshing(locale: locale)
                == "正在刷新——目前显示上次可用的结果。"
        )
        #expect(
            AttentionNotificationCopy.stale(
                reason: "索引未就绪。",
                locale: locale
            ) == "结果可能已过时。索引未就绪。"
        )
        #expect(
            AttentionNotificationCopy.refreshFailed(
                reason: "无法读取。",
                locale: locale
            ) == "刷新失败。目前显示上次可用的结果。无法读取。"
        )

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
