import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Attention presentation state")
@MainActor
struct AttentionPresentationStateTests {
    @Test("Sidebar Attention projects one exact visible Triptych aggregate")
    func totalCountProjection() {
        let reference = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            relativePath: "Analysis.md"
        )
        let first = AttentionQueueItem(
            kind: .possibleOrphan,
            severity: .information,
            note: reference,
            message: "Possible orphan."
        )
        let second = AttentionQueueItem(
            kind: .malformedMetadata,
            severity: .warning,
            note: reference,
            message: "The committed source changed."
        )
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: [],
            documents: [:],
            additionalAttention: [first, second]
        )
        let assignment = makeAssignment()

        #expect(AttentionPreferences.visibleTotalCount(
            catalog: catalog,
            assignment: assignment,
            dismissalLedgerData: Data()
        ) == 2)

        let dismissalLedger = AttentionDismissalLedger(
            dismissedUntilByItemID: [first.id: .distantFuture]
        )
        #expect(AttentionPreferences.visibleTotalCount(
            catalog: catalog,
            assignment: assignment,
            dismissalLedgerData: AttentionPreferences.encodeLedger(dismissalLedger)
        ) == 1)
        #expect(AttentionPreferences.visibleTotalCount(
            catalog: nil,
            assignment: assignment,
            dismissalLedgerData: Data()
        ) == nil)
        #expect(AttentionPreferences.visibleTotalCount(
            catalog: catalog,
            assignment: nil,
            dismissalLedgerData: Data()
        ) == nil)
    }

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

    @Test("The three visual groups cover each existing derived kind exactly once")
    func groupsAreCompleteAndExclusive() {
        let grouped = AttentionIssueGroup.allCases.flatMap(\.kinds)

        #expect(grouped.count == AttentionQueueKind.allCases.count)
        #expect(Set(grouped) == Set(AttentionQueueKind.allCases))
        #expect(Set(AttentionIssueGroup.identityAndMetadata.kinds) == Set([
            .malformedMetadata, .unresolvedIdentity,
        ]))
        #expect(Set(AttentionIssueGroup.structureAndConnections.kinds) == Set([
            .possibleOrphan, .brokenConnection, .ambiguousConnection,
        ]))
        #expect(Set(AttentionIssueGroup.revisionAndResearch.kinds) == Set([
            .synthesisMaterialChanged,
        ]))
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
        state.notificationFilter = .issue(.possibleOrphan)
        state.select("task-1")

        state.resetForWorkspaceSwitch()

        #expect(state.filter.query.isEmpty)
        #expect(state.notificationFilter == .all)
        #expect(state.selectedItemID == nil)
        #expect(state.noteScope == nil)
        #expect(state.workspaceSlot == .topicKnowledge)
    }

    @Test("Structural notification search matches the localized issue name")
    func localizedStructuralNotificationSearch() {
        let reference = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Reasons.md"
        )
        let orphan = AttentionQueueItem(
            kind: .possibleOrphan,
            severity: .information,
            note: reference,
            message: "No incoming or outgoing links"
        )
        let changed = AttentionQueueItem(
            kind: .malformedMetadata,
            severity: .warning,
            note: reference,
            message: "Invalid YAML"
        )

        let result = AttentionStructuralNotificationSearch.apply(
            to: [orphan, changed],
            filter: AttentionQueueFilter(query: "可能孤立"),
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(result == [orphan])

        let reasonResult = AttentionStructuralNotificationSearch.apply(
            to: [orphan, changed],
            filter: AttentionQueueFilter(query: "没有传入或传出链接"),
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(reasonResult == [orphan])
    }

    @Test("Notification empty and refresh state copy resolves in the interface locale")
    func localizedNotificationStateCopy() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(
            AttentionNotificationCopy.emptyDescription(
                noteScoped: false,
                locale: locale
            ) == "此范围内没有需要关注的 Action 活动、暂定提醒或可见派生问题。"
        )
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

        let reference = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Reasons.md"
        )
        let issueMessages = [
            ("Invalid YAML", "YAML 无效"),
            ("No incoming or outgoing links", "没有传入或传出链接"),
            ("Identity not confirmed", "身份尚未确认"),
            ("Multiple candidates", "有多个候选项"),
            ("Multiple matching Notes", "有多个匹配的笔记"),
            ("Multiple matching headings", "有多个匹配的标题"),
            ("Missing Note", "笔记缺失"),
            ("Missing heading", "标题缺失"),
            ("Missing block", "块缺失"),
            ("Invalid relationship endpoint", "关联端点无效"),
            (
                "A selected Analysis changed after Synthesize",
                "某篇已选分析在综合后发生了更改"
            ),
        ]
        for (message, expected) in issueMessages {
            let item = AttentionQueueItem(
                kind: .brokenConnection,
                severity: .warning,
                note: reference,
                message: message
            )
            #expect(
                AttentionIssueCopy.message(for: item, locale: locale)
                    == expected
            )
        }
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

    @Test("Action activities obey exact Note scope, affected-note scope, kind, and query filters")
    func activityNotificationScopeAndFilter() {
        let triptychID = UUID()
        let noteA = UUID()
        let noteB = UUID()
        let targetA = ResearchActivityNotification(
            triptychID: triptychID,
            runID: UUID(),
            actionID: .analyze,
            targetNoteID: noteA,
            targetTitle: "Agency Analysis",
            state: .running,
            activity: nil,
            result: nil,
            affectedNotes: [],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let targetB = ResearchActivityNotification(
            triptychID: triptychID,
            runID: UUID(),
            actionID: .critique,
            targetNoteID: noteB,
            targetTitle: "Value Draft",
            state: .needsAttention,
            activity: nil,
            result: nil,
            affectedNotes: [],
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let affectsA = ResearchActivityNotification(
            triptychID: triptychID,
            runID: UUID(),
            actionID: .synthesize,
            targetNoteID: noteB,
            targetTitle: "Cross-note Synthesis",
            state: .resultReady,
            activity: nil,
            result: nil,
            affectedNotes: [
                WorkspaceResearchAffectedNote(noteID: noteA, title: "Agency Topic")
            ],
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let notifications = [targetA, targetB, affectsA]

        #expect(ResearchActivityNotificationQuery.apply(
            notifications: notifications,
            noteID: nil,
            filter: AttentionQueueFilter(query: "综合"),
            locale: Locale(identifier: "zh-Hans")
        ) == [affectsA])

        #expect(ResearchActivityNotificationQuery.apply(
            notifications: notifications,
            noteID: nil,
            filter: AttentionQueueFilter()
        ).map(\.runID) == notifications.map(\.runID))
        #expect(ResearchActivityNotificationQuery.apply(
            notifications: notifications,
            noteID: noteA,
            filter: AttentionQueueFilter()
        ).map(\.runID) == [targetA.runID, affectsA.runID])
        #expect(ResearchActivityNotificationQuery.apply(
            notifications: notifications,
            noteID: noteB,
            filter: AttentionQueueFilter(query: "needs attention")
        ).map(\.runID) == [targetB.runID])
        #expect(ResearchActivityNotificationQuery.apply(
            notifications: notifications,
            noteID: noteB,
            filter: AttentionQueueFilter(query: "需要关注"),
            locale: Locale(identifier: "zh-Hans")
        ).map(\.runID) == [targetB.runID])
        #expect(ResearchActivityNotificationQuery.apply(
            notifications: notifications,
            noteID: noteA,
            filter: AttentionQueueFilter(query: "agency topic")
        ).map(\.runID) == [affectsA.runID])
        #expect(!AttentionNotificationFilter.issue(.possibleOrphan).showsActivities)
        #expect(AttentionNotificationFilter.activities.showsActivities)
    }

    @Test("Inspector Note paths resolve only an exact stable catalog identity")
    func activityNotificationStableNoteResolution() {
        let stableNoteID = UUID()
        let vaultID = UUID()
        let scopedPath = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Topics/Agency.md"
        )
        let catalogNote = WorkspaceCatalogNote(
            reference: VaultNoteReference(
                vaultID: vaultID,
                vaultName: "Topics",
                vaultRole: .topicKnowledge,
                relativePath: scopedPath.relativePath,
                stableNoteID: stableNoteID.uuidString.lowercased()
            ),
            title: "Agency",
            fingerprint: DocumentFingerprint(content: "agency"),
            validationWarnings: []
        )

        #expect(ResearchActivityNotificationQuery.stableNoteID(
            for: scopedPath,
            in: [catalogNote]
        ) == stableNoteID)
        #expect(ResearchActivityNotificationQuery.stableNoteID(
            for: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Topics/Other.md"
            ),
            in: [catalogNote]
        ) == nil)
    }

    private func makeAssignment() -> TriptychAssignment {
        let analyses = RegisteredVault(
            name: "Analyses",
            role: .sourceCorpus,
            canonicalPath: "/fixtures/Analyses"
        )
        let topics = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixtures/Topics"
        )
        let works = RegisteredVault(
            name: "Works",
            role: .draftProject,
            canonicalPath: "/fixtures/Works"
        )
        return TriptychAssignment(
            triptych: ScholiumTriptych(
                paperAnalysisVaultID: analyses.id,
                topicKnowledgeVaultID: topics.id,
                outputVaultID: works.id
            ),
            vaults: [
                .paperAnalysis: analyses,
                .topicKnowledge: topics,
                .output: works,
            ],
            hasCommonParent: true
        )
    }
}
